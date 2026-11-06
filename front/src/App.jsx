import { useEffect, useMemo, useRef, useState } from 'react'
import loguitoSistemaAlmacen from './LoguitoSistemaAlmacen.svg'

const API_URL = import.meta.env.VITE_API_URL ?? ''
const SESSION_KEY = 'login-general-session'

function nombreProductoSaldo(item) {
  return item?.idProducto === 31 || String(item?.producto || '').trim().toLowerCase() === 'tm_venta'
    ? 'Tigo Money'
    : item?.producto
}

function saldoConNombresVisibles(saldo) {
  return { ...saldo, productos: (saldo.productos || []).map((item) => ({ ...item, producto: nombreProductoSaldo(item) })) }
}

function detectarDispositivoMovil() {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') return false
  const agente = navigator.userAgent || ''
  const agenteMovil = /Android|iPhone|iPad|iPod|Mobile|Tablet|Silk|Kindle/i.test(agente)
  const tabletModoEscritorio = /Macintosh/i.test(agente) && navigator.maxTouchPoints > 1
  const pantallaTactilMovil = navigator.maxTouchPoints > 1 && window.matchMedia('(max-width: 1366px)').matches
  return agenteMovil || tabletModoEscritorio || pantallaTactilMovil
}

async function api(path, options = {}) {
  let response
  try {
    response = await fetch(`${API_URL}${path}`, {
      ...options,
      headers: { 'Content-Type': 'application/json', ...options.headers },
    })
  } catch {
    throw new Error('No se pudo conectar con el servidor. Verifica tu conexión e intenta nuevamente.')
  }
  if (!response.ok) {
    const body = await response.json().catch(() => null)
    const error = new Error(body?.message ?? 'No se pudo completar la solicitud.')
    error.status = response.status
    throw error
  }
  return response.status === 204 ? null : response.json()
}

async function escucharEventosPedidos(token, signal, onPedido) {
  const response = await fetch(`${API_URL}/api/auth/almacen/eventos`, {
    headers: { Accept: 'text/event-stream', Authorization: `Bearer ${token}` },
    signal,
  })
  if (!response.ok || !response.body) throw new Error('No se pudo conectar a las notificaciones.')
  const reader = response.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  while (!signal.aborted) {
    const { value, done } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true }).replace(/\r/g, '')
    let separator = buffer.indexOf('\n\n')
    while (separator >= 0) {
      const block = buffer.slice(0, separator)
      buffer = buffer.slice(separator + 2)
      const eventName = block.split('\n').find((line) => line.startsWith('event:'))?.slice(6).trim()
      const data = block.split('\n').filter((line) => line.startsWith('data:')).map((line) => line.slice(5).trim()).join('\n')
      if (eventName === 'pedido-nuevo' && data) onPedido(JSON.parse(data))
      separator = buffer.indexOf('\n\n')
    }
  }
}

async function escucharCascadaSistemas(token, jobId, signal, onConectado, onProgreso) {
  const response = await fetch(`${API_URL}/api/auth/sistemas/cascada/eventos/${jobId}`, {
    headers: { Accept: 'text/event-stream', Authorization: `Bearer ${token}` },
    signal,
  })
  if (!response.ok || !response.body) throw new Error('No se pudo conectar al canal de progreso.')
  const reader = response.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  while (!signal.aborted) {
    const { value, done } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true }).replace(/\r/g, '')
    let separator = buffer.indexOf('\n\n')
    while (separator >= 0) {
      const block = buffer.slice(0, separator)
      buffer = buffer.slice(separator + 2)
      const eventName = block.split('\n').find((line) => line.startsWith('event:'))?.slice(6).trim()
      const data = block.split('\n').filter((line) => line.startsWith('data:')).map((line) => line.slice(5).trim()).join('\n')
      if (eventName === 'conectado') onConectado?.()
      if (eventName === 'progreso' && data) onProgreso?.(JSON.parse(data))
      separator = buffer.indexOf('\n\n')
    }
  }
}

async function escucharScanner(tokenSesion, tokenVinculo, signal, onCodigo, ruta = '/api/scanner/vinculaciones') {
  const response = await fetch(`${API_URL}${ruta}/${tokenVinculo}/eventos`, {
    headers: { Accept: 'text/event-stream', Authorization: `Bearer ${tokenSesion}` },
    signal,
  })
  if (!response.ok || !response.body) {
    const error = new Error('No se pudo abrir el canal del escáner.')
    error.status = response.status
    throw error
  }
  const reader = response.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  while (!signal.aborted) {
    const { value, done } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true }).replace(/\r/g, '')
    let separator = buffer.indexOf('\n\n')
    while (separator >= 0) {
      const block = buffer.slice(0, separator)
      buffer = buffer.slice(separator + 2)
      const eventName = block.split('\n').find((line) => line.startsWith('event:'))?.slice(6).trim()
      const data = block.split('\n').filter((line) => line.startsWith('data:')).map((line) => line.slice(5).trim()).join('\n')
      if (eventName === 'codigo' && data) onCodigo(JSON.parse(data))
      separator = buffer.indexOf('\n\n')
    }
  }
}

function esVinculacionNoDisponible(error) {
  const mensaje = String(error?.message || '').toLowerCase()
  return error?.status === 404
    || error?.status === 410
    || mensaje.includes('vinculacion no existe')
    || mensaje.includes('vinculación no existe')
    || mensaje.includes('vinculacion expiro')
    || mensaje.includes('vinculación expiró')
}

function DeviceLinkPanel({ session }) {
  const [vinculo, setVinculo] = useState(null)
  const [qrVinculo, setQrVinculo] = useState('')
  const [lecturas, setLecturas] = useState([])
  const [error, setError] = useState('')
  const [creando, setCreando] = useState(false)
  const [listaCerrada, setListaCerrada] = useState(false)
  const [ahora, setAhora] = useState(() => Date.now())
  const [modoTira, setModoTira] = useState('rango')
  const [listaMaster, setListaMaster] = useState([])
  const [validandoTira, setValidandoTira] = useState(false)

  useEffect(() => {
    const timer = setInterval(() => setAhora(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [])

  useEffect(() => {
    if (!vinculo) return undefined
    const controller = new AbortController()
    let active = true
    let reconnectTimer
    const conectar = async () => {
      try {
        await escucharScanner(session.token, vinculo.token, controller.signal, (lectura) => {
          setLecturas((actuales) => [{ ...lectura, id: `${lectura.fecha}-${crypto.randomUUID()}` }, ...actuales].slice(0, 100))
          setListaCerrada(false)
          setError('')
        })
        if (active) reconnectTimer = setTimeout(conectar, 2000)
      } catch (err) {
        if (active && err.name !== 'AbortError') {
          setError('Reconectando el canal del escáner…')
          reconnectTimer = setTimeout(conectar, 2500)
        }
      }
    }
    conectar()
    return () => { active = false; controller.abort(); clearTimeout(reconnectTimer) }
  }, [session.token, vinculo])

  const segundosRestantes = vinculo ? Math.max(0, Math.floor((new Date(vinculo.expira).getTime() - ahora) / 1000)) : 0
  const tiempoRestante = `${String(Math.floor(segundosRestantes / 60)).padStart(2, '0')}:${String(segundosRestantes % 60).padStart(2, '0')}`

  async function crearVinculo() {
    setCreando(true)
    setError('')
    setLecturas([])
    setListaCerrada(false)
    try {
      const creado = await api('/api/scanner/vinculaciones', { method: 'POST', headers: { Authorization: `Bearer ${session.token}` } })
      const basePublica = creado.publicUrl || window.location.origin
      const urlTelefono = `${basePublica.replace(/\/$/, '')}/scanner/${creado.token}`
      const { default: QRCode } = await import('qrcode')
      setQrVinculo(await QRCode.toDataURL(urlTelefono, { width: 320, margin: 2, errorCorrectionLevel: 'M', color: { dark: '#172f43', light: '#ffffff' } }))
      setVinculo({ ...creado, urlTelefono })
    } catch (err) {
      setError(err.message)
    } finally {
      setCreando(false)
    }
  }

  async function cerrarVinculo() {
    if (vinculo) await api(`/api/scanner/vinculaciones/${vinculo.token}`, { method: 'DELETE', headers: { Authorization: `Bearer ${session.token}` } }).catch(() => null)
    setVinculo(null)
    setQrVinculo('')
    setLecturas([])
    setListaCerrada(false)
  }

  function obtenerImeisTira() {
    const escaneados = [...lecturas].reverse().map((item) => String(item.codigo ?? '').replace(/[^0-9]/g, ''))
    if (modoTira === 'individual') return escaneados
    if (escaneados.length !== 2) throw new Error('Para calcular una tira debes escanear exactamente el primer y el último IMEI.')
    const primero = BigInt(escaneados[0])
    const ultimo = BigInt(escaneados[1])
    if (ultimo < primero) throw new Error('El último IMEI debe ser mayor o igual que el primero.')
    const cantidad = ultimo - primero + 1n
    if (cantidad > 1000n) throw new Error('Una tira no puede superar 1000 tarjetas.')
    return Array.from({ length: Number(cantidad) }, (_, index) => String(primero + BigInt(index)))
  }

  async function validarYAgregarTira() {
    setError('')
    setValidandoTira(true)
    try {
      const imeis = obtenerImeisTira()
      if (!imeis.length) throw new Error('Escanea al menos un IMEI para formar la tira.')
      if (new Set(imeis).size !== imeis.length) throw new Error('La tira contiene IMEI repetidos.')
      const repetido = imeis.find((imei) => listaMaster.some((tira) => tira.imeis.includes(imei)))
      if (repetido) throw new Error(`El IMEI ${repetido} ya pertenece a otra tira de la Lista Master.`)
      const validacion = await api('/api/scanner/productos/validar', {
        method: 'POST',
        headers: { Authorization: `Bearer ${session.token}` },
        body: JSON.stringify({ imeis }),
      })
      const numero = listaMaster.length + 1
      setListaMaster((actual) => [...actual, { id: crypto.randomUUID(), numero, modo: modoTira, imeis, validacion }])
      setLecturas([])
      setListaCerrada(false)
      if (!validacion.tiraValida) setError(`Tira ${numero} agregada con ${validacion.total - validacion.validos} IMEI inválido(s).`)
    } catch (err) {
      setError(err.message)
    } finally {
      setValidandoTira(false)
    }
  }

  function eliminarTira(id) {
    setListaMaster((actual) => actual.filter((tira) => tira.id !== id).map((tira, index) => ({ ...tira, numero: index + 1 })))
  }

  useEffect(() => {
    if (vinculo && segundosRestantes === 0) {
      queueMicrotask(() => {
        setError('La vinculación expiró. Vincula nuevamente el teléfono.')
        setVinculo(null)
        setQrVinculo('')
      })
    }
  }, [segundosRestantes, vinculo])

  return (
    <section className="device-link-panel">
      <div className="device-link-heading"><p>CONTROL DE DISPOSITIVOS</p><h2>Vincular dispositivo</h2><span>Usa un teléfono como lector QR durante una hora</span></div>
      {!vinculo ? (
        <div className="device-link-empty">
          <span>QR</span>
          <h3>Conectar un teléfono</h3>
          <p>Genera un código de vinculación y escanéalo con el teléfono. Después, la cámara quedará habilitada como lector continuo.</p>
          <button type="button" onClick={crearVinculo} disabled={creando}>{creando ? 'Generando…' : 'Vincular teléfono'}</button>
          {error && <small className="device-error">{error}</small>}
        </div>
      ) : (
        <div className="scanner-link-workspace">
          <aside className="scanner-pair-card">
            <div className={`scanner-pair-status ${listaCerrada ? 'closed' : ''}`}><span /> {listaCerrada ? 'LISTA CERRADA' : 'VINCULACIÓN ACTIVA'}</div>
            <img src={qrVinculo} alt="QR para vincular el teléfono" />
            <h3>Escanea este QR con el teléfono</h3>
            <p>El dispositivo permanecerá conectado durante una hora.</p>
            <a className="scanner-public-link" href={vinculo.urlTelefono} target="_blank" rel="noreferrer">Abrir enlace de ngrok</a>
            <div className="scanner-expiry"><span>Tiempo restante</span><strong>{tiempoRestante}</strong></div>
            <button type="button" onClick={cerrarVinculo}>Desvincular teléfono</button>
          </aside>
          <section className="scanner-readings">
            <div className="scanner-readings-head"><div><p>LISTA MASTER · TIRA {listaMaster.length + 1}</p><h3>Captura de tarjetas</h3></div><span>{lecturas.length}</span></div>
            <div className="strip-mode-selector">
              <button className={modoTira === 'individual' ? 'active' : ''} type="button" onClick={() => { setModoTira('individual'); setLecturas([]) }}>Uno por uno</button>
              <button className={modoTira === 'rango' ? 'active' : ''} type="button" onClick={() => { setModoTira('rango'); setLecturas([]) }}>Primer y último</button>
            </div>
            <p className="strip-instruction">{modoTira === 'individual' ? 'Escanea todas las tarjetas de esta tira.' : 'Escanea primero el IMEI inicial y después el IMEI final. El rango es inclusivo.'}</p>
            {error && <div className="scanner-message scanner-message--error">{error}</div>}
            {lecturas.length === 0 ? <div className="scanner-message">Esperando la primera lectura desde el teléfono…</div> : (
              <div className="scanner-code-list">{lecturas.map((lectura, index) => <article className={index === 0 ? 'new' : ''} key={lectura.id}><span>{String(lecturas.length - index).padStart(2, '0')}</span><strong>{lectura.codigo}</strong><time>{new Date(lectura.fecha).toLocaleTimeString('es-BO')}</time></article>)}</div>
            )}
            <div className="strip-actions"><button type="button" onClick={() => setLecturas([])} disabled={!lecturas.length}>Limpiar</button><button type="button" onClick={validarYAgregarTira} disabled={!lecturas.length || validandoTira}>{validandoTira ? 'Validando…' : 'Validar y agregar tira'}</button></div>
          </section>
          <section className="master-list-panel">
            <div className="master-list-head"><div><p>LISTA GENERAL</p><h3>Lista Master</h3></div><strong>{listaMaster.reduce((total, tira) => total + tira.imeis.length, 0)} tarjetas</strong></div>
            {!listaMaster.length ? <div className="master-list-empty">Aún no agregaste tiras.</div> : listaMaster.map((tira) => (
              <article className={`master-strip ${tira.validacion.tiraValida ? 'valid' : 'invalid'}`} key={tira.id}>
                <div><span>TIRA {tira.numero}</span><strong>{tira.imeis.length} tarjetas · {tira.modo === 'rango' ? 'Calculada' : 'Una por una'}</strong><small>{tira.imeis[0]} — {tira.imeis.at(-1)}</small></div>
                <b>{tira.validacion.tiraValida ? 'Válida' : `${tira.validacion.total - tira.validacion.validos} inválida(s)`}</b>
                <button type="button" onClick={() => eliminarTira(tira.id)}>Quitar</button>
                {!tira.validacion.tiraValida && <ul>{tira.validacion.productos.filter((item) => !item.valido).map((item) => <li key={item.imei}><strong>{item.imei}</strong>: {item.motivo}</li>)}</ul>}
              </article>
            ))}
          </section>
        </div>
      )}
    </section>
  )
}

function WarehouseDevicePanel({ vinculo, qr, creando, error, segundos, onCrear, onCerrar }) {
  const tiempo = `${String(Math.floor(segundos / 60)).padStart(2, '0')}:${String(segundos % 60).padStart(2, '0')}`
  return (
    <section className="device-link-panel">
      <div className="device-link-heading"><p>CONTROL DE DISPOSITIVOS</p><h2>Vincular dispositivo</h2><span>Un telefono puede escanear productos para varios pedidos durante una hora</span></div>
      {!vinculo ? (
        <div className="device-link-empty">
          <span>QR</span><h3>Conectar un telefono</h3>
          <p>La vinculacion permanece activa al cambiar entre pedidos y productos.</p>
          <button type="button" onClick={onCrear} disabled={creando}>{creando ? 'Generando…' : 'Vincular telefono'}</button>
          {error && <small className="device-error">{error}</small>}
        </div>
      ) : (
        <div className="scanner-link-workspace scanner-link-workspace--persistent">
          <aside className="scanner-pair-card">
            <div className="scanner-pair-status"><span /> VINCULACION ACTIVA</div>
            <img src={qr} alt="QR para vincular el telefono" />
            <h3>Escanea este QR con el telefono</h3>
            <p>Luego abre cualquier pedido y selecciona el producto que cargaras.</p>
            <a className="scanner-public-link" href={vinculo.urlTelefono} target="_blank" rel="noreferrer">Abrir enlace de ngrok</a>
            <div className="scanner-expiry"><span>Tiempo restante</span><strong>{tiempo}</strong></div>
            <button type="button" onClick={onCerrar}>Desvincular telefono</button>
          </aside>
          <section className="persistent-scanner-guide">
            <p>DISPOSITIVO LISTO</p><h3>Utilizalo en todos los pedidos</h3>
            <ol><li>Abre un pedido pendiente.</li><li>Selecciona el producto que cargaras.</li><li>Escanea y valida las tiras desde el telefono.</li><li>Completa todos los productos y aprueba.</li></ol>
            {error && <div className="scanner-message scanner-message--error">{error}</div>}
          </section>
        </div>
      )}
    </section>
  )
}

function mensajeErrorCamara(err) {
  if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
    return `La cámara solo funciona en una página segura (https). Estás en ${window.location.origin}: abre el enlace https del QR de vinculación.`
  }
  const texto = `${err?.name || ''} ${err?.message || err || ''}`
  if (/NotAllowed|Permission|denied/i.test(texto)) {
    return 'Se negó el permiso de cámara. En iPhone: Ajustes › Safari › Cámara › Preguntar o Permitir, y recarga la página.'
  }
  if (/NotReadable|TrackStart|in use|Could not start/i.test(texto)) {
    return 'La cámara está ocupada por otra aplicación o pestaña. Ciérrala e intenta nuevamente.'
  }
  if (/NotFound|Overconstrained|no camera|Requested device/i.test(texto)) {
    return 'No se encontró una cámara disponible en este dispositivo.'
  }
  return 'No se pudo abrir la cámara. Verifica el permiso del navegador y que estés usando HTTPS.'
}

function PhoneScanner({ token }) {
  const [estado, setEstado] = useState('validando')
  const [modoLectura, setModoLectura] = useState('qr')
  const [sesion, setSesion] = useState(null)
  const [ultimoCodigo, setUltimoCodigo] = useState('')
  const [codigoPendiente, setCodigoPendiente] = useState('')
  const [validacionPendiente, setValidacionPendiente] = useState(null)
  const [error, setError] = useState('')
  const [errorRevinculacion, setErrorRevinculacion] = useState('')
  const [ahoraTelefono, setAhoraTelefono] = useState(() => Date.now())
  const scannerRef = useRef(null)
  const audioContextRef = useRef(null)
  const ultimaLecturaRef = useRef({ codigo: '', fecha: 0 })
  const revinculandoRef = useRef(false)

  useEffect(() => {
    let active = true
    api(`/api/scanner/publico/${token}`).then((data) => { if (active) { setSesion(data); setEstado('listo') } }).catch((err) => { if (active) { setError(err.message); setEstado('error') } })
    return () => { active = false }
  }, [token])

  useEffect(() => {
    if (!sesion?.expira || estado === 'error' || estado === 'revinculando') return undefined
    const timer = setInterval(() => setAhoraTelefono(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [sesion?.expira, estado])

  useEffect(() => {
    if (!sesion?.expira || estado === 'error' || estado === 'revinculando') return
    if (new Date(sesion.expira).getTime() > ahoraTelefono) return
    const scanner = scannerRef.current
    if (scanner?.isScanning) scanner.stop().catch(() => null)
    scannerRef.current = null
    queueMicrotask(() => {
      setError('La vinculación expiró. Genera un código QR nuevo desde la computadora.')
      setEstado('error')
    })
  }, [ahoraTelefono, sesion?.expira, estado])

  useEffect(() => {
    if (!sesion || estado === 'error' || estado === 'revinculando') return undefined
    let active = true
    const verificarVinculo = () => {
      api(`/api/scanner/publico/${token}`).catch((err) => {
        if (!active || !esVinculacionNoDisponible(err)) return
        const scanner = scannerRef.current
        if (scanner?.isScanning) scanner.stop().catch(() => null)
        scannerRef.current = null
        setCodigoPendiente('')
        setValidacionPendiente(null)
        setError('La vinculación dejó de existir. Genera un código QR nuevo desde la computadora.')
        setEstado('error')
      })
    }
    const timer = setInterval(verificarVinculo, 10000)
    return () => { active = false; clearInterval(timer) }
  }, [estado, sesion, token])

  async function marcarVinculacionNoDisponible(mensaje) {
    const scanner = scannerRef.current
    try {
      if (scanner?.isScanning) await scanner.stop()
      if (scanner) scanner.clear()
    } catch {
      // El lector puede haber sido destruido por el navegador al perder la conexión.
    }
    scannerRef.current = null
    setCodigoPendiente('')
    setValidacionPendiente(null)
    setError(mensaje || 'La vinculación ya no está disponible. Genera un código QR nuevo desde la computadora.')
    setEstado('error')
  }

  async function volverAVincular() {
    setErrorRevinculacion('')
    setError('')
    setEstado('revinculando')
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))
    try {
      const { Html5Qrcode, Html5QrcodeSupportedFormats } = await import('html5-qrcode')
      const scanner = new Html5Qrcode('phone-relink-reader', { formatsToSupport: [Html5QrcodeSupportedFormats.QR_CODE] })
      scannerRef.current = scanner
      await scanner.start(
        { facingMode: 'environment' },
        {
          fps: 12,
          qrbox: (width, height) => {
            const lado = Math.floor(Math.min(width, height) * 0.72)
            return { width: lado, height: lado }
          },
          aspectRatio: 1,
        },
        async (contenidoQr) => {
          if (revinculandoRef.current) return
          revinculandoRef.current = true
          try {
            const url = new URL(contenidoQr, window.location.origin)
            const coincidencia = url.pathname.match(/^\/scanner\/([^/]+)\/?$/)
            if (!coincidencia) throw new Error('Este QR no corresponde a una vinculación del scanner.')
            const tokenNuevo = decodeURIComponent(coincidencia[1])
            await api(`/api/scanner/publico/${tokenNuevo}`)
            if (scanner.isScanning) await scanner.stop()
            scanner.clear()
            scannerRef.current = null
            window.location.replace(`${window.location.origin}/scanner/${encodeURIComponent(tokenNuevo)}`)
          } catch (err) {
            setErrorRevinculacion(err.message)
            revinculandoRef.current = false
          }
        },
        () => {},
      )
    } catch {
      scannerRef.current = null
      setError('No se pudo abrir la cámara para leer el nuevo QR. Revisa el permiso de cámara e inténtalo nuevamente.')
      setEstado('error')
    }
  }

  async function confirmarCodigo() {
    const codigo = codigoPendiente.trim().replace(/[-‐‑‒–—]/g, '')
    if (!codigo || !validacionPendiente?.valido) return
    const ahoraLectura = Date.now()
    ultimaLecturaRef.current = { codigo, fecha: ahoraLectura }
    try {
      await api(`/api/scanner/publico/${token}/lecturas`, { method: 'POST', body: JSON.stringify({ codigo }) })
      setUltimoCodigo(codigo)
      setCodigoPendiente('')
      setValidacionPendiente(null)
      setError('')
      if (navigator.vibrate) navigator.vibrate(80)
      scannerRef.current?.resume()
      setEstado('escaneando')
    } catch (err) {
      if (esVinculacionNoDisponible(err)) await marcarVinculacionNoDisponible(err.message)
      else setError(err.message)
    }
  }

  async function revisarCodigo(texto, modo = modoLectura) {
    const codigoLeido = texto.trim().replace(/[-‐‑‒–—]/g, '')
    const codigo = modo === 'barras' ? codigoLeido.slice(0, -1) : codigoLeido
    if (!codigo || codigoPendiente) return
    // El reloj se consulta únicamente al recibir una lectura física.
    // eslint-disable-next-line react-hooks/purity
    const ahoraLectura = Date.now()
    if (ultimaLecturaRef.current.codigo === codigo && ahoraLectura - ultimaLecturaRef.current.fecha < 1800) return
    scannerRef.current?.pause(true)
    emitirPitidoScanner()
    setCodigoPendiente(codigo)
    setValidacionPendiente(null)
    setEstado('validando-codigo')
    try {
      const resultado = await api(`/api/scanner/publico/${token}/validar`, {
        method: 'POST',
        body: JSON.stringify({ codigo }),
      })
      setValidacionPendiente(resultado.productos[0])
      setError('')
      setEstado('revisando')
    } catch (err) {
      if (esVinculacionNoDisponible(err)) await marcarVinculacionNoDisponible(err.message)
      else {
        setError(err.message)
        setEstado('revisando')
      }
    }
  }

  function emitirPitidoScanner() {
    const audio = audioContextRef.current
    if (!audio || audio.state !== 'running') return
    const inicio = audio.currentTime
    const oscilador = audio.createOscillator()
    const volumen = audio.createGain()
    oscilador.type = 'square'
    oscilador.frequency.setValueAtTime(1450, inicio)
    volumen.gain.setValueAtTime(0.0001, inicio)
    volumen.gain.exponentialRampToValueAtTime(0.18, inicio + 0.008)
    volumen.gain.exponentialRampToValueAtTime(0.0001, inicio + 0.095)
    oscilador.connect(volumen)
    volumen.connect(audio.destination)
    oscilador.start(inicio)
    oscilador.stop(inicio + 0.1)
  }

  function escanearOtro() {
    setCodigoPendiente('')
    setValidacionPendiente(null)
    setError('')
    scannerRef.current?.resume()
    setEstado('escaneando')
  }

  async function iniciarCamara(modo = modoLectura) {
    setError('')
    try {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext
      if (AudioContextClass) {
        if (!audioContextRef.current || audioContextRef.current.state === 'closed') audioContextRef.current = new AudioContextClass()
        if (audioContextRef.current.state === 'suspended') await audioContextRef.current.resume()
      }
      const { Html5Qrcode, Html5QrcodeSupportedFormats } = await import('html5-qrcode')
      const formatos = modo === 'qr'
        ? [Html5QrcodeSupportedFormats.QR_CODE]
        : [
            Html5QrcodeSupportedFormats.CODE_128,
            Html5QrcodeSupportedFormats.CODE_39,
            Html5QrcodeSupportedFormats.EAN_13,
            Html5QrcodeSupportedFormats.EAN_8,
            Html5QrcodeSupportedFormats.UPC_A,
            Html5QrcodeSupportedFormats.UPC_E,
            Html5QrcodeSupportedFormats.ITF,
          ]
      const scanner = new Html5Qrcode('phone-qr-reader', { formatsToSupport: formatos })
      scannerRef.current = scanner
      const qrbox = modo === 'qr'
        ? (viewfinderWidth, viewfinderHeight) => {
            const lado = Math.floor(Math.min(viewfinderWidth, viewfinderHeight) * 0.72)
            return { width: lado, height: lado }
          }
        : (viewfinderWidth, viewfinderHeight) => ({
            width: Math.floor(viewfinderWidth * 0.9),
            height: Math.max(90, Math.floor(viewfinderHeight * 0.34)),
          })
      await scanner.start(
        { facingMode: 'environment' },
        { fps: 15, qrbox, aspectRatio: modo === 'qr' ? 1 : 1.777778 },
        (codigoLeido) => revisarCodigo(codigoLeido, modo),
        () => {},
      )
      setEstado('escaneando')
    } catch (err) {
      setError(mensajeErrorCamara(err))
      scannerRef.current = null
    }
  }

  async function cambiarModoLectura(nuevoModo) {
    if (nuevoModo === modoLectura || estado === 'validando-codigo' || estado === 'revisando') return
    setError('')
    const scanner = scannerRef.current
    try {
      if (scanner?.isScanning) await scanner.stop()
      if (scanner) scanner.clear()
      scannerRef.current = null
      setModoLectura(nuevoModo)
      if (estado === 'escaneando') await iniciarCamara(nuevoModo)
    } catch {
      setEstado('listo')
      setModoLectura(nuevoModo)
      setError('No se pudo cambiar el tipo de lector. Activa la cámara nuevamente.')
    }
  }

  useEffect(() => () => {
    const scanner = scannerRef.current
    if (scanner?.isScanning) scanner.stop().catch(() => null)
    const audio = audioContextRef.current
    if (audio && audio.state !== 'closed') audio.close().catch(() => null)
  }, [])

  return (
    <main className="phone-scanner-page">
      <header><BrandMark /><div><strong>Lector operativo</strong><span>{estado === 'revinculando' ? 'Nueva vinculación' : estado === 'error' ? 'Dispositivo sin vincular' : 'Dispositivo vinculado'}</span></div></header>
      <section className="phone-scanner-card">
        {estado === 'validando' && <div className="phone-scanner-state">Validando vinculación…</div>}
        {estado === 'error' && <div className="phone-scanner-state phone-scanner-state--error"><strong>Vinculación no disponible</strong><span>{error}</span><small>Genera una vinculación nueva en la computadora y escanea su código QR.</small><button className="phone-start-button" type="button" onClick={volverAVincular}>Volver a vincular</button></div>}
        {estado === 'revinculando' && <div className="phone-relink-state"><strong>Escanea el nuevo QR</strong><span>Abre Vincular dispositivo en la computadora y genera otro código.</span><div id="phone-relink-reader" />{errorRevinculacion && <div className="phone-scanner-error">{errorRevinculacion}</div>}</div>}
        {(estado === 'listo' || estado === 'escaneando' || estado === 'validando-codigo' || estado === 'revisando') && <>
          <div className="phone-scanner-head"><span className="live-dot" /><div><strong>{estado === 'escaneando' ? 'Escáner activo' : 'Teléfono vinculado'}</strong><small>Válido hasta {new Date(sesion.expira).toLocaleTimeString('es-BO')}</small></div></div>
          <div className="phone-reader-mode" role="group" aria-label="Tipo de código">
            <button className={modoLectura === 'qr' ? 'active' : ''} type="button" onClick={() => cambiarModoLectura('qr')} disabled={estado === 'validando-codigo' || estado === 'revisando'}>QR</button>
            <button className={modoLectura === 'barras' ? 'active' : ''} type="button" onClick={() => cambiarModoLectura('barras')} disabled={estado === 'validando-codigo' || estado === 'revisando'}>Código de barras</button>
          </div>
          <div className="phone-reader-caption"><strong>{modoLectura === 'qr' ? 'LECTOR QR' : 'LECTOR DE CÓDIGO DE BARRAS'}</strong><span>{modoLectura === 'qr' ? 'Tarjetas con código QR' : 'Chips con código lineal'}</span></div>
          <div id="phone-qr-reader" className={`phone-qr-reader phone-qr-reader--${modoLectura} ${estado === 'revisando' ? 'paused' : ''}`} />
          {estado === 'listo' && <button className="phone-start-button" type="button" onClick={() => iniciarCamara(modoLectura)}>Activar cámara</button>}
          {estado === 'validando-codigo' && <div className="phone-scan-review"><span>VALIDANDO IMEI</span><strong>{codigoPendiente}</strong><p>Consultando producto y disponibilidad…</p></div>}
          {estado === 'revisando' && <div className={`phone-scan-review ${validacionPendiente?.valido ? 'valid' : 'invalid'}`}><span>{validacionPendiente?.valido ? 'IMEI VÁLIDO' : 'IMEI NO VÁLIDO'}</span><strong>{codigoPendiente}</strong>{validacionPendiente?.valido ? <p>{validacionPendiente.productoEncontrado} · Disponible para {validacionPendiente.productoEsperado}</p> : <p>{validacionPendiente?.motivo || error}</p>}<div>{validacionPendiente?.valido ? <button type="button" onClick={confirmarCodigo}>Enviar IMEI</button> : <button type="button" onClick={escanearOtro}>Escanear otro</button>}</div></div>}
          {ultimoCodigo && <div className="phone-last-code"><span>ÚLTIMA LECTURA</span><strong>{ultimoCodigo}</strong><small>Enviado correctamente</small></div>}
          {error && <div className="phone-scanner-error">{error}</div>}
          <p className="phone-scanner-help">{modoLectura === 'qr' ? 'Centra el código QR dentro del recuadro.' : 'Coloca el código completo dentro del marco horizontal. El último dígito se descarta automáticamente antes de validar.'} Revisa el contenido y confirma cada lectura para enviarla a la computadora.</p>
        </>}
      </section>
    </main>
  )
}

function BrandMark() {
  return <img className="brand-logo" src={loguitoSistemaAlmacen} alt="" aria-hidden="true" />
}

function TutorialFlowMock({ mock }) {
  const [filtroTecnico, setFiltroTecnico] = useState('hoy')
  const [detalleAbierto, setDetalleAbierto] = useState(false)
  const [cuadreEnviado, setCuadreEnviado] = useState(false)
  const [rutaActiva, setRutaActiva] = useState('RUTA-12')
  const [avanceEscaneo, setAvanceEscaneo] = useState(6)
  const [vinculacionPaso, setVinculacionPaso] = useState(0)
  const [verVersionModificada, setVerVersionModificada] = useState(false)

  useEffect(() => {
    setFiltroTecnico('hoy')
    setDetalleAbierto(false)
    setCuadreEnviado(false)
    setRutaActiva('RUTA-12')
    setAvanceEscaneo(6)
    setVinculacionPaso(0)
    setVerVersionModificada(false)
  }, [mock])

  if (!mock) return null

  if (mock === 'tech-orders') {
    const pedidos = filtroTecnico === 'hoy'
      ? [
        { id: 1842, estado: 'Aprobado', total: 'Bs 1,250.00' },
        { id: 1845, estado: 'Pendiente', total: 'Bs 840.00' },
      ]
      : [
        { id: 1831, estado: 'Aprobado', total: 'Bs 990.00' },
        { id: 1822, estado: 'Modificado', total: 'Bs 1,100.00' },
        { id: 1817, estado: 'Aprobado', total: 'Bs 720.00' },
      ]
    return (
      <section className="guided-tour-mock" aria-label="Simulación de pedidos técnico">
        <div className="guided-tour-mock-head">
          <strong>Mock de capacitación: pedidos del vendedor</strong>
          <small>Simulación local. No consulta ni guarda en la base.</small>
        </div>
        <div className="guided-tour-chip-row">
          <button type="button" className={filtroTecnico === 'hoy' ? 'active' : ''} onClick={() => setFiltroTecnico('hoy')}>Hoy</button>
          <button type="button" className={filtroTecnico === 'historico' ? 'active' : ''} onClick={() => setFiltroTecnico('historico')}>Histórico</button>
        </div>
        <div className="guided-tour-mock-list">
          {pedidos.map((pedido) => (
            <article key={pedido.id}>
              <span>#{pedido.id}</span>
              <b>{pedido.estado}</b>
              <strong>{pedido.total}</strong>
            </article>
          ))}
        </div>
      </section>
    )
  }

  if (mock === 'tech-detail') {
    return (
      <section className="guided-tour-mock" aria-label="Simulación de detalle de pedido técnico">
        <div className="guided-tour-mock-head">
          <strong>Mock de detalle del pedido</strong>
          <small>Practica cómo revisar cambios de almacén antes de continuar.</small>
        </div>
        <div className="guided-tour-chip-row">
          <button type="button" onClick={() => setDetalleAbierto((value) => !value)}>{detalleAbierto ? 'Ocultar detalle' : 'Ver detalle'}</button>
        </div>
        {detalleAbierto && (
          <div className="guided-tour-mock-panel">
            <div className="guided-tour-mock-meta"><span>Pedido #1845</span><b>Modificado por almacén</b></div>
            <p>Comentario: "Se ajustó T20 por disponibilidad parcial".</p>
            <div className="guided-tour-mini-table">
              <span>Producto</span><span>Cant.</span><span>Estado</span>
              <strong>T10</strong><strong>8</strong><strong>Sin cambio</strong>
              <strong>T20</strong><strong>4</strong><strong>Ajustado</strong>
            </div>
          </div>
        )}
      </section>
    )
  }

  if (mock === 'tech-cashup') {
    return (
      <section className="guided-tour-mock" aria-label="Simulación de cuadre técnico">
        <div className="guided-tour-mock-head">
          <strong>Mock de Mi Cuadre (preliminar)</strong>
          <small>El envío solo representa declaración; no mueve inventario en esta simulación.</small>
        </div>
        <div className="guided-tour-mock-panel">
          <div className="guided-tour-mini-table">
            <span>Producto</span><span>Sobrante</span><span>Vendido</span>
            <strong>T10</strong><strong>20</strong><strong>80</strong>
            <strong>TM_Venta</strong><strong>Bs 350</strong><strong>Bs 1,150</strong>
          </div>
          <div className="guided-tour-chip-row">
            <button type="button" className={cuadreEnviado ? 'active' : ''} onClick={() => setCuadreEnviado(true)}>Simular envío preliminar</button>
            {cuadreEnviado && <span className="guided-tour-pill">Estado: Pendiente de revisión de almacén</span>}
          </div>
        </div>
      </section>
    )
  }

  if (mock === 'warehouse-orders') {
    const pendientesPorRuta = {
      'RUTA-12': 3,
      'RUTA-07': 1,
      'RUTA-21': 0,
    }
    return (
      <section className="guided-tour-mock" aria-label="Simulación de pedidos almacén">
        <div className="guided-tour-mock-head">
          <strong>Mock de cola de pedidos por ruta</strong>
          <small>Usa esto para explicar priorización y revisión por técnico/ruta.</small>
        </div>
        <div className="guided-tour-route-grid">
          {Object.entries(pendientesPorRuta).map(([ruta, cantidad]) => (
            <button key={ruta} type="button" className={rutaActiva === ruta ? 'active' : ''} onClick={() => setRutaActiva(ruta)}>
              <span>{ruta}</span>
              <b>{cantidad} pendientes</b>
            </button>
          ))}
        </div>
        <div className="guided-tour-mock-panel">
          <div className="guided-tour-mock-meta"><span>{rutaActiva}</span><b>Técnico: Juan Perez</b></div>
          <p>Pedido #1902 · 14 unidades · Estado pendiente.</p>
          <small>En operación real, al abrir detalle se revisa observación, cantidades y productos antes de aprobar.</small>
        </div>
      </section>
    )
  }

  if (mock === 'warehouse-approval') {
    const total = 10
    const completo = avanceEscaneo >= total
    return (
      <section className="guided-tour-mock" aria-label="Simulación de aprobación de pedido">
        <div className="guided-tour-mock-head">
          <strong>Mock de detalle + aprobación</strong>
          <small>Escaneo simulado y validación previa a aprobar. Sin transacciones reales.</small>
        </div>
        <div className="guided-tour-mock-panel">
          <div className="guided-tour-mock-meta"><span>Detalle #441 · Producto T10</span><b>{avanceEscaneo} / {total} IMEI</b></div>
          <div className="guided-tour-progress-line"><span style={{ width: `${(avanceEscaneo / total) * 100}%` }} /></div>
          <div className="guided-tour-chip-row">
            <button type="button" onClick={() => setAvanceEscaneo((value) => Math.min(total, value + 1))}>Simular lectura válida</button>
            <button type="button" onClick={() => setAvanceEscaneo((value) => Math.max(0, value - 1))}>Quitar lectura</button>
          </div>
          <div className="guided-tour-chip-row">
            <button type="button" className={completo ? 'active' : ''} disabled={!completo}>Aprobar pedido (mock)</button>
            <span className="guided-tour-pill">{completo ? 'Listo para aprobar' : 'Faltan IMEI por cargar'}</span>
          </div>
        </div>
      </section>
    )
  }

  if (mock === 'warehouse-linking') {
    const pasos = [
      'Token generado',
      'QR escaneado desde teléfono',
      'Dispositivo vinculado por 1 hora',
      'Lecturas SSE activas',
    ]
    return (
      <section className="guided-tour-mock" aria-label="Simulación de vinculación de dispositivo">
        <div className="guided-tour-mock-head">
          <strong>Mock de vinculación del escáner</strong>
          <small>Capacitación del flujo QR/telefono sin abrir cámara real.</small>
        </div>
        <div className="guided-tour-mock-list guided-tour-mock-list--steps">
          {pasos.map((paso, idx) => (
            <article key={paso} className={idx <= vinculacionPaso ? 'active' : ''}>
              <span>{idx + 1}</span>
              <strong>{paso}</strong>
            </article>
          ))}
        </div>
        <div className="guided-tour-chip-row">
          <button type="button" onClick={() => setVinculacionPaso((value) => Math.min(pasos.length - 1, value + 1))}>Siguiente paso</button>
          <button type="button" onClick={() => setVinculacionPaso(0)}>Reiniciar</button>
        </div>
      </section>
    )
  }

  if (mock === 'warehouse-cashup') {
    return (
      <section className="guided-tour-mock" aria-label="Simulación de revisión de cuadre almacén">
        <div className="guided-tour-mock-head">
          <strong>Mock de revisión de cuadre</strong>
          <small>Comparación entre versión original del vendedor y versión ajustada por almacén.</small>
        </div>
        <div className="guided-tour-chip-row">
          <button type="button" className={!verVersionModificada ? 'active' : ''} onClick={() => setVerVersionModificada(false)}>Ver original</button>
          <button type="button" className={verVersionModificada ? 'active' : ''} onClick={() => setVerVersionModificada(true)}>Ver modificada</button>
        </div>
        <div className="guided-tour-mock-panel">
          <div className="guided-tour-mini-table">
            <span>Producto</span><span>Sobrante</span><span>Vendido</span>
            <strong>T20</strong><strong>{verVersionModificada ? 9 : 11}</strong><strong>{verVersionModificada ? 31 : 29}</strong>
            <strong>TM_Venta</strong><strong>{verVersionModificada ? 'Bs 280' : 'Bs 300'}</strong><strong>{verVersionModificada ? 'Bs 1,220' : 'Bs 1,200'}</strong>
          </div>
          <span className="guided-tour-pill">{verVersionModificada ? 'Modificado por almacén' : 'Declarado por vendedor'}</span>
        </div>
      </section>
    )
  }

  return null
}

function GuidedTour({ steps, onClose }) {
  const [index, setIndex] = useState(0)
  const [rect, setRect] = useState(null)
  const [coachRect, setCoachRect] = useState(null)
  const step = steps[index]

  useEffect(() => {
    function locate() {
      const element = document.querySelector(step.target)
      if (!element) {
        setRect(null)
        setCoachRect(null)
        return
      }
      const bounds = element.getBoundingClientRect()
      const width = Math.min(460, window.innerWidth - 24)
      const preferredTop = bounds.bottom + 12
      const fallbackTop = Math.max(10, bounds.top - 280)
      const top = preferredTop + 270 <= window.innerHeight ? preferredTop : fallbackTop
      const left = Math.min(Math.max(10, bounds.left), Math.max(10, window.innerWidth - width - 10))
      setRect({
        top: Math.max(8, bounds.top - 7),
        left: Math.max(8, bounds.left - 7),
        width: Math.min(window.innerWidth - 16, bounds.width + 14),
        height: Math.min(window.innerHeight - 16, bounds.height + 14),
      })
      setCoachRect({ top, left, width })
    }
    const element = document.querySelector(step.target)
    element?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' })
    const timer = window.setTimeout(locate, 180)
    window.addEventListener('resize', locate)
    window.addEventListener('scroll', locate, true)
    return () => {
      window.clearTimeout(timer)
      window.removeEventListener('resize', locate)
      window.removeEventListener('scroll', locate, true)
    }
  }, [step.target])

  useEffect(() => {
    function keydown(event) {
      if (event.key === 'Escape') onClose()
      if (event.key === 'ArrowRight' && index < steps.length - 1) setIndex((value) => value + 1)
      if (event.key === 'ArrowLeft' && index > 0) setIndex((value) => value - 1)
    }
    window.addEventListener('keydown', keydown)
    return () => window.removeEventListener('keydown', keydown)
  }, [index, onClose, steps.length])

  return (
    <div className="guided-tour" role="dialog" aria-modal="true" aria-label="Tutorial del sistema">
      <div className="guided-tour-shade" />
      {rect && <div className="guided-tour-focus" style={rect}><span>{index + 1}</span></div>}
      <header className="guided-tour-hud">
        <div className="guided-tour-progress"><span style={{ width: `${((index + 1) / steps.length) * 100}%` }} /></div>
        <div className="guided-tour-hud-row">
          <span className="guided-tour-count">ENTRENAMIENTO {index + 1}/{steps.length}</span>
          <div>
            {index > 0 && <button type="button" onClick={() => setIndex((value) => value - 1)}>Atrás</button>}
            <button type="button" onClick={() => index === steps.length - 1 ? onClose() : setIndex((value) => value + 1)}>{index === steps.length - 1 ? 'Finalizar' : 'Siguiente'}</button>
            <button type="button" className="skip" onClick={onClose}>Salir</button>
          </div>
        </div>
      </header>
      {coachRect && (
        <section className="guided-tour-coach" style={coachRect}>
          <h2>{step.title}</h2>
          <p>{step.description}</p>
          <TutorialFlowMock mock={step.mock} />
        </section>
      )}
    </div>
  )
}

function LoginFieldIcon({ type }) {
  if (type === 'user') return <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="3.5" /><path d="M5.5 19c.8-3.4 3-5.2 6.5-5.2s5.7 1.8 6.5 5.2" /></svg>
  if (type === 'password') return <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="10" width="14" height="10" rx="2" /><path d="M8 10V7.5a4 4 0 018 0V10M12 14v2.5" /></svg>
  return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20h16M6 20V8l6-4 6 4v12M9 11h2v2H9zM13 11h2v2h-2zM9 16h6" /></svg>
}

function EyeIcon({ visible }) {
  return visible
    ? <svg viewBox="0 0 24 24"><path d="M3 3l18 18M10.6 10.7a2 2 0 002.7 2.7M9.9 4.2A10.8 10.8 0 0112 4c5.5 0 9 5.2 9 5.2a15.8 15.8 0 01-3 3.7M6.6 6.6C4.3 8.1 3 10.2 3 10.2s3.5 5.2 9 5.2c1 0 2-.2 2.8-.5" /></svg>
    : <svg viewBox="0 0 24 24"><path d="M3 12s3.5-5.2 9-5.2S21 12 21 12s-3.5 5.2-9 5.2S3 12 3 12z" /><circle cx="12" cy="12" r="2.5" /></svg>
}

function LoginFormFields({
  idPrefix, usuario, setUsuario, password, setPassword, mostrarPassword, setMostrarPassword,
  idSucursal, setIdSucursal, sucursales, cargandoSucursales, error, enviando, onSubmit,
}) {
  return <>
    <div className="login-card-badge"><span /> Conexi&oacute;n segura</div>
    <div className="login-form-shell">
      <div className="login-mobile-mark" aria-hidden="true"><BrandMark /></div>
      <div className="form-heading"><p className="eyebrow">ACCESO SEGURO</p><h2>Iniciar sesión</h2><span>Ingresa tus credenciales para continuar.</span></div>
      <form onSubmit={onSubmit} noValidate>
        <label htmlFor={`${idPrefix}-usuario`}>Usuario</label>
        <div className="field"><span className="login-field-icon"><LoginFieldIcon type="user" /></span><input id={`${idPrefix}-usuario`} autoComplete="username" placeholder="Ej. jperez" value={usuario} aria-invalid={Boolean(error)} required onChange={(e) => setUsuario(e.target.value)} /></div>
        <label htmlFor={`${idPrefix}-password`}>Contraseña</label>
        <div className="field"><span className="login-field-icon"><LoginFieldIcon type="password" /></span><input id={`${idPrefix}-password`} type={mostrarPassword ? 'text' : 'password'} autoComplete="current-password" placeholder="Ingresa tu contraseña" value={password} aria-invalid={Boolean(error)} required onChange={(e) => setPassword(e.target.value)} /><button className="icon-button" type="button" aria-label={mostrarPassword ? 'Ocultar contraseña' : 'Mostrar contraseña'} aria-pressed={mostrarPassword} onClick={() => setMostrarPassword((value) => !value)}><EyeIcon visible={mostrarPassword} /></button></div>
        <label htmlFor={`${idPrefix}-sucursal`}>Sucursal</label>
        <div className="field"><span className="login-field-icon"><LoginFieldIcon type="branch" /></span><select id={`${idPrefix}-sucursal`} value={idSucursal} disabled={cargandoSucursales} aria-invalid={Boolean(error)} required onChange={(e) => setIdSucursal(e.target.value)}><option value="">{cargandoSucursales ? 'Cargando sucursales…' : 'Selecciona una sucursal'}</option>{sucursales.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}</select></div>
        {error && <div className="error-message" role="alert"><span>!</span>{error}</div>}
        <button className="primary-button" type="submit" disabled={enviando || cargandoSucursales}>{enviando && <span className="spinner" />}{enviando ? 'Verificando…' : 'Ingresar al sistema'}<b>→</b></button>
      </form>
      <div className="login-security-note"><span>✓</span><p><strong>Sesi&oacute;n protegida</strong><small>Autenticaci&oacute;n JWT y conexi&oacute;n cifrada</small></p></div>
    </div>
  </>
}

const integer = new Intl.NumberFormat('es-BO')
const money = new Intl.NumberFormat('es-BO', { style: 'currency', currency: 'BOB' })
const dateTime = new Intl.DateTimeFormat('es-BO', { dateStyle: 'medium', timeStyle: 'short' })

const PASOS_CARGA_CUADRE = {
  preparando: ['Consultando el saldo de la ruta', 'Cargando productos asignados', 'Preparando la Lista Master'],
  finalizando: ['Validando los sobrantes registrados', 'Calculando productos vendidos', 'Actualizando el inventario de la ruta', 'Registrando el cuadre y sus tiras'],
}

function CuadreLoadingModal({ tipo }) {
  const [inicio] = useState(() => Date.now())
  const [ahora, setAhora] = useState(() => Date.now())
  useEffect(() => {
    const timer = setInterval(() => setAhora(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [])
  const pasos = PASOS_CARGA_CUADRE[tipo] || PASOS_CARGA_CUADRE.finalizando
  const segundos = Math.floor((ahora - inicio) / 1000)
  const pasoActual = Math.min(pasos.length - 1, Math.floor(segundos / 4))
  return (
    <div className="cuadre-loading-overlay" role="presentation">
      <section className="cuadre-loading-dialog" role="alertdialog" aria-modal="true" aria-busy="true" aria-live="polite">
        <span className="cuadre-loading-spinner" aria-hidden="true" />
        <h3>{tipo === 'preparando' ? 'Preparando el cuadre' : 'Guardando el cuadre'}</h3>
        <p>{tipo === 'preparando' ? 'Estamos cargando los productos de la ruta.' : 'Esto puede tardar varios minutos cuando la ruta tiene muchos productos. No cierres ni recargues esta ventana.'}</p>
        <ol>{pasos.map((paso, index) => <li key={paso} className={index < pasoActual ? 'done' : index === pasoActual ? 'active' : ''}>{paso}</li>)}</ol>
        <small>Tiempo transcurrido · {String(Math.floor(segundos / 60)).padStart(2, '0')}:{String(segundos % 60).padStart(2, '0')}</small>
      </section>
    </div>
  )
}

function MyCuadrePanel({ session, rutaObjetivo = null, onCompletado, endpointFinalizarOverride = '' }) {
  const [iniciado, setIniciado] = useState(false)
  const [productos, setProductos] = useState([])
  const [idProducto, setIdProducto] = useState('')
  const [modo, setModo] = useState('rango')
  const [lecturas, setLecturas] = useState([])
  const [listaMaster, setListaMaster] = useState([])
  const [entradaManual, setEntradaManual] = useState('')
  const [cantidad, setCantidad] = useState('')
  const [imeisRevision, setImeisRevision] = useState(null)
  const [sobranteTigoMoney, setSobranteTigoMoney] = useState('')
  const [efectivizacionTigoMoney, setEfectivizacionTigoMoney] = useState('')
  const [sobranteChip, setSobranteChip] = useState('')
  const [modoLectura, setModoLectura] = useState('qr')
  const [camaraActiva, setCamaraActiva] = useState(false)
  const [cargando, setCargando] = useState(false)
  const [tipoCarga, setTipoCarga] = useState(null)
  const [validando, setValidando] = useState(false)
  const [error, setError] = useState('')
  const [resultado, setResultado] = useState(null)
  const [estadoHoy, setEstadoHoy] = useState(null)
  const [consultandoEstado, setConsultandoEstado] = useState(true)
  const [observacion, setObservacion] = useState('')
  const [vinculo, setVinculo] = useState(null)
  const [qrVinculo, setQrVinculo] = useState('')
  const [ahora, setAhora] = useState(() => Date.now())
  const scannerRef = useRef(null)
  const ultimaLecturaRef = useRef({ codigo: '', fecha: 0 })
  const producto = productos.find((item) => item.idProducto === Number(idProducto))
  const esTigoMoney = producto?.tipoProducto?.toLowerCase() === 'tigomoney'
    && producto?.producto?.toUpperCase() === 'TM_VENTA'
  const esChip = producto?.tipoProducto?.toLowerCase() === 'chip'
  const chipsSinRegistrar = productos.filter((item) => item.tipoProducto?.toLowerCase() === 'chip'
    && item.cantidadAsignada > 0 && !listaMaster.some((tira) => tira.idProducto === item.idProducto))
  const esCuadreAlmacen = Boolean(rutaObjetivo)
  const authCuadreBase = esCuadreAlmacen
    ? `/api/auth/almacen/cuadres/rutas/${rutaObjetivo.idRuta}`
    : '/api/auth/cuadre'
  const scannerCuadreBase = esCuadreAlmacen
    ? '/api/scanner/almacen/cuadre/vinculaciones'
    : '/api/scanner/cuadre/vinculaciones'

  const normalizar = (valor, tipo = modoLectura) => {
    const limpio = String(valor ?? '').trim().replace(/[-‐‑‒–—]/g, '').replace(/[^0-9]/g, '')
    return tipo === 'barras' && limpio.length > 1 ? limpio.slice(0, -1) : limpio
  }

  useEffect(() => {
    let activo = true
    setConsultandoEstado(true)
    api(`${authCuadreBase}/hoy`, { headers: { Authorization: `Bearer ${session.token}` } })
      .then((data) => { if (activo) setEstadoHoy(data) })
      .catch((err) => { if (activo) setError(err.message) })
      .finally(() => { if (activo) setConsultandoEstado(false) })
    return () => { activo = false }
  }, [authCuadreBase, session.token])

  useEffect(() => () => {
    const scanner = scannerRef.current
    if (scanner?.isScanning) scanner.stop().catch(() => null)
  }, [])

  useEffect(() => {
    if (!vinculo) return undefined
    const controller = new AbortController()
    escucharScanner(session.token, vinculo.token, controller.signal, (lectura) => {
      setLecturas((actuales) => {
        if (actuales.includes(lectura.codigo)) return actuales
        if (modo === 'cantidad') return [lectura.codigo]
        if (modo === 'rango' && actuales.length >= 2) return actuales
        return [...actuales, lectura.codigo]
      })
      setImeisRevision(null)
      setError('')
    }, scannerCuadreBase).catch((err) => {
      if (err.name !== 'AbortError') setError('Se perdió el canal del scanner vinculado.')
    })
    return () => controller.abort()
  }, [session.token, vinculo, modo, scannerCuadreBase])

  useEffect(() => {
    if (!vinculo || !idProducto || esTigoMoney || esChip) return
    const registrados = [...listaMaster, { idProducto: Number(idProducto), imeis: lecturas }]
      .filter((item) => item.idProducto === Number(idProducto)).flatMap((item) => item.imeis)
    api(`${scannerCuadreBase}/${vinculo.token}/contexto`, {
      method: 'POST', headers: { Authorization: `Bearer ${session.token}` },
      body: JSON.stringify({ idRuta: rutaObjetivo?.idRuta, idProducto: Number(idProducto), imeisRegistrados: [...new Set(registrados)] }),
    }).catch((err) => setError(err.message))
  }, [idProducto, lecturas, listaMaster, session.token, vinculo, esTigoMoney, esChip, scannerCuadreBase, rutaObjetivo?.idRuta])

  useEffect(() => {
    if (!vinculo) return undefined
    const timer = setInterval(() => setAhora(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [vinculo])

  const segundosVinculo = vinculo ? Math.max(0, Math.floor((new Date(vinculo.expira).getTime() - ahora) / 1000)) : 0

  async function iniciarCuadre() {
    setCargando(true)
    setTipoCarga('preparando')
    setError('')
    try {
      const data = await api(`${authCuadreBase}/productos`, { headers: { Authorization: `Bearer ${session.token}` } })
      setProductos(data)
      setIdProducto(data[0] ? String(data[0].idProducto) : '')
      setIniciado(true)
    } catch (err) {
      setError(err.message)
    } finally {
      setCargando(false)
      setTipoCarga(null)
    }
  }

  async function validarImeis(imeis) {
    const respuesta = await api(`${authCuadreBase}/validar`, {
      method: 'POST', headers: { Authorization: `Bearer ${session.token}` },
      body: JSON.stringify({ idProducto: Number(idProducto), imeis }),
    })
    if (!respuesta.tiraValida) {
      const invalidos = respuesta.productos.filter((item) => !item.valido)
      const detalle = invalidos.slice(0, 5).map((item) => `${item.imei}: ${item.motivo || 'No es válido.'}`).join(' | ')
      throw new Error(invalidos.length > 5 ? `${invalidos.length} IMEI no son válidos. ${detalle} | …` : detalle || 'Un IMEI no es válido.')
    }
    return respuesta
  }

  async function registrarLectura(valor, tipo = modoLectura) {
    const imei = normalizar(valor, tipo)
    if (!idProducto) throw new Error('Selecciona primero el producto.')
    if (!imei || imei.length > 18) throw new Error('Ingresa un IMEI numérico válido.')
    if (modo === 'rango' && lecturas.length >= 2) throw new Error('Ya ingresaste el primer y el último IMEI de la tira.')
    if (lecturas.includes(imei) || listaMaster.some((tira) => tira.imeis.includes(imei))) throw new Error('Ese IMEI ya está en la Lista Master.')
    setValidando(true)
    try {
      await validarImeis([imei])
      setLecturas((actuales) => modo === 'cantidad' ? [imei] : [...actuales, imei])
      setImeisRevision(null)
      setEntradaManual('')
      setError('')
      if (navigator.vibrate) navigator.vibrate(70)
    } finally {
      setValidando(false)
    }
  }

  async function confirmarManual(event) {
    event.preventDefault()
    try { await registrarLectura(entradaManual, 'qr') } catch (err) { setError(err.message) }
  }

  async function iniciarCamara() {
    setError('')
    setCamaraActiva(true)
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))
    try {
      const { Html5Qrcode, Html5QrcodeSupportedFormats } = await import('html5-qrcode')
      const formatos = modoLectura === 'qr'
        ? [Html5QrcodeSupportedFormats.QR_CODE]
        : [Html5QrcodeSupportedFormats.CODE_128, Html5QrcodeSupportedFormats.CODE_39, Html5QrcodeSupportedFormats.EAN_13, Html5QrcodeSupportedFormats.ITF]
      const scanner = new Html5Qrcode('cuadre-camera-reader', { formatsToSupport: formatos })
      scannerRef.current = scanner
      await scanner.start(
        { facingMode: 'environment' },
        { fps: 12, qrbox: modoLectura === 'qr' ? { width: 230, height: 230 } : { width: 290, height: 110 } },
        async (codigo) => {
          const normalizado = normalizar(codigo)
          const tiempo = Date.now()
          if (ultimaLecturaRef.current.codigo === normalizado && tiempo - ultimaLecturaRef.current.fecha < 1800) return
          ultimaLecturaRef.current = { codigo: normalizado, fecha: tiempo }
          scanner.pause(true)
          try { await registrarLectura(codigo) } catch (err) { setError(err.message) }
          if (scanner.isScanning) scanner.resume()
        },
        () => {},
      )
    } catch (err) {
      setCamaraActiva(false)
      scannerRef.current = null
      setError(`${mensajeErrorCamara(err)} También puedes usar el ingreso manual.`)
    }
  }

  async function detenerCamara() {
    const scanner = scannerRef.current
    try {
      if (scanner?.isScanning) await scanner.stop()
      if (scanner) scanner.clear()
    } catch { /* El navegador puede haber cerrado la cámara. */ }
    scannerRef.current = null
    setCamaraActiva(false)
  }

  async function crearVinculo() {
    setError('')
    try {
      const creado = await api(scannerCuadreBase, { method: 'POST', headers: { Authorization: `Bearer ${session.token}` } })
      const base = creado.publicUrl || window.location.origin
      const urlTelefono = `${base.replace(/\/$/, '')}/scanner/${creado.token}`
      const { default: QRCode } = await import('qrcode')
      setQrVinculo(await QRCode.toDataURL(urlTelefono, { width: 260, margin: 2, errorCorrectionLevel: 'M' }))
      setVinculo({ ...creado, urlTelefono })
    } catch (err) { setError(err.message) }
  }

  async function cerrarVinculo() {
    if (vinculo) await api(`${scannerCuadreBase}/${vinculo.token}`, { method: 'DELETE', headers: { Authorization: `Bearer ${session.token}` } }).catch(() => null)
    setVinculo(null)
    setQrVinculo('')
  }

  function calcularImeisTira() {
    if (modo === 'individual') return [...lecturas]
    if (modo === 'rango') {
      if (lecturas.length !== 2) throw new Error('Ingresa primero el IMEI inicial y después el IMEI final.')
      const inicio = BigInt(lecturas[0]); const fin = BigInt(lecturas[1])
      if (fin < inicio) throw new Error('El IMEI final debe ser mayor o igual al inicial.')
      if (fin - inicio + 1n > 1000n) throw new Error('Una tira no puede superar 1000 unidades.')
      return Array.from({ length: Number(fin - inicio + 1n) }, (_, index) => String(inicio + BigInt(index)))
    }
    if (lecturas.length !== 1) throw new Error('Confirma exactamente el primer IMEI de la tira.')
    if (!/^\d+$/.test(String(cantidad).trim())) throw new Error('Ingresa una cantidad entera mayor que cero.')
    const total = Number(cantidad)
    if (!Number.isSafeInteger(total) || total < 1 || total > 1000) throw new Error('La cantidad debe estar entre 1 y 1000.')
    const inicio = BigInt(lecturas[0])
    return Array.from({ length: total }, (_, index) => String(inicio + BigInt(index)))
  }

  function mostrarInformacionTira() {
    setError('')
    try {
      const imeis = calcularImeisTira()
      if (!imeis.length) throw new Error('Ingresa al menos un IMEI para revisar la tira.')
      setImeisRevision(imeis)
    } catch (err) {
      setImeisRevision(null)
      setError(err.message)
    }
  }

  function limpiarTira() {
    setLecturas([])
    setImeisRevision(null)
    setCantidad('')
  }

  async function agregarTira() {
    setValidando(true)
    setError('')
    try {
      const imeis = imeisRevision ?? calcularImeisTira()
      if (!imeis.length) throw new Error('Ingresa al menos un IMEI.')
      if (new Set(imeis).size !== imeis.length) throw new Error('La tira contiene IMEI repetidos.')
      const repetido = imeis.find((imei) => listaMaster.some((tira) => tira.imeis.includes(imei)))
      if (repetido) throw new Error(`El IMEI ${repetido} ya está en otra tira.`)
      await validarImeis(imeis)
      setListaMaster((actual) => [...actual, { id: crypto.randomUUID(), numero: actual.length + 1, idProducto: Number(idProducto), producto: producto.producto, modo, imeis }])
      limpiarTira()
    } catch (err) { setError(err.message) } finally { setValidando(false) }
  }

  function cambiarProducto(valor) {
    setIdProducto(valor)
    limpiarTira()
    setSobranteTigoMoney('')
    setEfectivizacionTigoMoney('')
    setSobranteChip('')
    setError('')
  }

  function agregarChip() {
    setError('')
    const sobrante = Number(sobranteChip)
    if (!producto || !esChip) {
      setError('Selecciona un chip para registrar su sobrante.')
      return
    }
    if (sobranteChip === '' || !Number.isInteger(sobrante) || sobrante < 0) {
      setError('Ingresa una cantidad sobrante entera mayor o igual a cero.')
      return
    }
    if (sobrante > producto.cantidadAsignada) {
      setError(`El sobrante no puede superar el saldo del chip: ${integer.format(producto.cantidadAsignada)}.`)
      return
    }
    if (listaMaster.some((item) => item.idProducto === producto.idProducto)) {
      setError(`${producto.producto} ya está en la Lista Master. Quítalo para cambiar la cantidad.`)
      return
    }
    setListaMaster((actual) => [...actual, {
      id: crypto.randomUUID(), numero: actual.length + 1, idProducto: producto.idProducto,
      producto: producto.producto, modo: 'chip_cantidad', imeis: [], cantidadManual: sobrante,
      saldo: producto.cantidadAsignada,
    }])
    setSobranteChip('')
  }

  function cambiarModo(nuevo) {
    setModo(nuevo)
    limpiarTira()
    setError('')
  }

  function agregarTigoMoney() {
    setError('')
    const sobrante = Number(sobranteTigoMoney)
    const efectivizacion = Number(efectivizacionTigoMoney)
    if (!producto || !esTigoMoney) {
      setError('Selecciona TM_Venta para registrar el sobrante manual.')
      return
    }
    if (!Number.isInteger(sobrante) || sobrante < 0) {
      setError('Ingresa un sobrante de Tigo Money entero mayor o igual a cero.')
      return
    }
    if (!Number.isInteger(efectivizacion) || efectivizacion < 0) {
      setError('Ingresa una efectivización entera mayor o igual a cero.')
      return
    }
    if (sobrante > producto.cantidadAsignada + efectivizacion) {
      setError(`El sobrante no puede superar el saldo más la efectivización: ${integer.format(producto.cantidadAsignada + efectivizacion)}.`)
      return
    }
    if (listaMaster.some((item) => item.idProducto === producto.idProducto && item.modo === 'tigo_money')) {
      setError('TM_Venta ya fue agregado a la Lista Master. Quítalo para cambiar el monto.')
      return
    }
    setListaMaster((actual) => [...actual, {
      id: crypto.randomUUID(), numero: actual.length + 1, idProducto: producto.idProducto,
      producto: producto.producto, modo: 'tigo_money', imeis: [], cantidadManual: sobrante,
      cantidadEfectivizada: efectivizacion,
    }])
    setSobranteTigoMoney('')
    setEfectivizacionTigoMoney('')
  }

  async function finalizar() {
    if (!listaMaster.length) { setError('Agrega al menos una tira a la Lista Master.'); return }
    const avisoChips = chipsSinRegistrar.length
      ? `\n\nNo registraste sobrante para: ${chipsSinRegistrar.map((item) => item.producto).join(', ')}. Todo su saldo se dará por vendido.`
      : ''
    if (!window.confirm(`Se marcarán como vendidos todos los productos no incluidos como sobrantes.${avisoChips}\n\n¿Confirmas el cuadre?`)) return
    setCargando(true)
    setTipoCarga('finalizando')
    setError('')
    try {
      const data = await api(endpointFinalizarOverride || `${authCuadreBase}/finalizar`, {
        method: 'POST', headers: { Authorization: `Bearer ${session.token}` },
        body: JSON.stringify({ observacion, tiras: listaMaster.map(({ idProducto: productoId, numero, modo: modoTira, imeis, cantidadManual, cantidadEfectivizada }) => ({ idProducto: productoId, numeroTira: numero, modo: modoTira, imeis, cantidadManual, cantidadEfectivizada })) }),
      })
      await detenerCamara()
      await cerrarVinculo()
      setResultado(data)
      onCompletado?.(data)
    } catch (err) { setError(err.message) } finally { setCargando(false); setTipoCarga(null) }
  }

  return (
    <section className="my-balance-panel">
      {tipoCarga && <CuadreLoadingModal key={tipoCarga} tipo={tipoCarga} />}
      <header className="my-balance-heading"><div><p>{esCuadreAlmacen ? 'CUADRE ASISTIDO POR ALMACÉN' : 'CONTROL PERSONAL'}</p><h2>{esCuadreAlmacen ? `Cuadre de ${rutaObjetivo.ruta}` : 'Mi Cuadre'}</h2><span>{esCuadreAlmacen ? `${rutaObjetivo.tecnico} · registra los sobrantes de esta ruta.` : 'Registra por tiras los productos físicos que sobraron en tu ruta.'}</span></div>{iniciado && !resultado && <span className="my-balance-state"><i /> Cuadre en proceso</span>}</header>
      {consultandoEstado ? <div className="my-balance-empty my-balance-empty--checking"><span className="my-balance-icon">C</span><div><h3>Consultando cuadre de hoy</h3><p>Estamos verificando si la ruta ya realizó su cuadre.</p></div></div>
        : resultado ? <div className="cuadre-success"><span>✓</span><h3>{esCuadreAlmacen ? 'Cuadre registrado' : 'Cuadre enviado a almacén'}</h3><p>{esCuadreAlmacen ? 'Se creó el cuadre definitivo' : 'Se creó el cuadre preliminar'} <strong>#{resultado.idCuadre}</strong> para la ruta.</p><dl><div><dt>Sobrantes</dt><dd>{integer.format(resultado.totalSobrantes)}</dd></div><div><dt>Vendidos</dt><dd>{integer.format(resultado.totalVendidos)}</dd></div><div><dt>Total vendido</dt><dd>{money.format(resultado.total)}</dd></div></dl>{!esCuadreAlmacen && <small>El almacenero debe verificarlo y aprobarlo antes de afectar el inventario definitivo.</small>}</div>
          : estadoHoy?.existe ? <div className="cuadre-success cuadre-success--existing"><span>✓</span><h3>{estadoHoy.esPreliminar && estadoHoy.estadoAprobado === 1 ? 'Cuadre pendiente de aprobación' : 'Ya hay un cuadre para la fecha de hoy'}</h3><p>La <strong>RUTA {estadoHoy.idRuta}</strong> registró el cuadre <strong>#{estadoHoy.idCuadre}</strong> el {dateTime.format(new Date(estadoHoy.fecha))}.</p><small>{estadoHoy.esPreliminar && estadoHoy.estadoAprobado === 1 ? 'Fue enviado al almacén y todavía no modifica el saldo definitivo.' : estadoHoy.modificado ? 'El almacén aprobó una versión modificada y conservó tu versión original.' : 'Solo se permite realizar un cuadre por día.'}</small></div>
            : !iniciado ? <div className="my-balance-empty"><span className="my-balance-icon">C</span><div><h3>Cuadre de vendedor</h3><p>Al comenzar podrás usar la cámara de este teléfono, vincular otro dispositivo o ingresar los IMEI manualmente.</p></div><button type="button" onClick={iniciarCuadre} disabled={cargando}>{cargando ? 'Preparando…' : 'Hacer cuadre'}</button></div>
          : <div className="cuadre-workspace">
            <section className="cuadre-capture">
              <div className="cuadre-product-selector"><label>Producto que estás contando<select value={idProducto} onChange={(event) => cambiarProducto(event.target.value)}>{productos.map((item) => <option key={item.idProducto} value={item.idProducto}>{item.producto} · {item.tipoProducto} · saldo {item.cantidadAsignada}</option>)}</select></label></div>
              {esTigoMoney ? <div className="cuadre-tigo-money"><div className="cuadre-tigo-money-head"><span>TIGO MONEY</span><strong>Sobrante y efectivización</strong><p>Ingresa cuánto quedó como saldo y cuánto se efectivizó durante la jornada.</p></div><dl><div><dt>Saldo inicial</dt><dd>{integer.format(producto.cantidadAsignada)}</dd></div><div><dt>Vendido calculado</dt><dd>{sobranteTigoMoney !== '' && efectivizacionTigoMoney !== '' && Number(sobranteTigoMoney) >= 0 && Number(efectivizacionTigoMoney) >= 0 ? integer.format(Math.max(0, producto.cantidadAsignada + Number(efectivizacionTigoMoney) - Number(sobranteTigoMoney))) : '—'}</dd></div></dl><div className="cuadre-tigo-fields"><label>Sobrante de Tigo Money<input type="number" min="0" step="1" inputMode="numeric" value={sobranteTigoMoney} onChange={(event) => setSobranteTigoMoney(event.target.value)} placeholder="Ej.: 700" /></label><label>Cuánto efectivizó<input type="number" min="0" step="1" inputMode="numeric" value={efectivizacionTigoMoney} onChange={(event) => setEfectivizacionTigoMoney(event.target.value)} placeholder="Ej.: 300" /></label></div><button type="button" onClick={agregarTigoMoney} disabled={sobranteTigoMoney === '' || efectivizacionTigoMoney === ''}>Agregar a Lista Master</button><small>TM_Venta y TM_Compra se calcularán y guardarán con códigos inicial y final en 0.</small></div> : esChip ? <div className="cuadre-tigo-money cuadre-chip-count"><div className="cuadre-tigo-money-head"><span>CHIPS</span><strong>¿Cuántos chips sobraron?</strong><p>Escribe la cantidad que le queda al técnico. La diferencia con el saldo de la ruta se dará por vendida, empezando por los chips más antiguos.</p></div><dl><div><dt>Saldo actual</dt><dd>{integer.format(producto.cantidadAsignada)}</dd></div><div><dt>Vendidos</dt><dd>{sobranteChip !== '' && Number(sobranteChip) >= 0 && Number(sobranteChip) <= producto.cantidadAsignada ? integer.format(producto.cantidadAsignada - Number(sobranteChip)) : '—'}</dd></div></dl><div className="cuadre-tigo-fields"><label>Chips sobrantes<input type="number" min="0" max={producto.cantidadAsignada} step="1" inputMode="numeric" value={sobranteChip} onChange={(event) => setSobranteChip(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') { event.preventDefault(); agregarChip() } }} placeholder={`Ej.: ${Math.max(0, producto.cantidadAsignada - 2)}`} /></label></div><button type="button" onClick={agregarChip} disabled={sobranteChip === ''}>Agregar a Lista Master</button><small>No hace falta escanear: el sobrante queda como nuevo saldo de la ruta y se marcan como vendidos los chips más antiguos hasta completar la diferencia.</small></div> : <>
                <div className="cuadre-mode"><button className={modo === 'individual' ? 'active' : ''} type="button" onClick={() => cambiarModo('individual')}>Uno por uno</button><button className={modo === 'rango' ? 'active' : ''} type="button" onClick={() => cambiarModo('rango')}>Primero y último</button><button className={modo === 'cantidad' ? 'active' : ''} type="button" onClick={() => cambiarModo('cantidad')}>Por cantidad</button></div>
                <div className="cuadre-source-actions"><button type="button" onClick={camaraActiva ? detenerCamara : iniciarCamara}>{camaraActiva ? 'Cerrar cámara' : 'Usar cámara aquí'}</button><button type="button" onClick={vinculo ? cerrarVinculo : crearVinculo}>{vinculo ? 'Desvincular teléfono' : 'Vincular otro teléfono'}</button></div>
                {camaraActiva && <><div className="phone-reader-mode"><button className={modoLectura === 'qr' ? 'active' : ''} type="button" onClick={() => setModoLectura('qr')}>QR</button><button className={modoLectura === 'barras' ? 'active' : ''} type="button" onClick={() => setModoLectura('barras')}>Código de barras</button></div><div id="cuadre-camera-reader" className="cuadre-camera-reader" /></>}
                {vinculo && <div className="cuadre-linked"><img src={qrVinculo} alt="QR para vincular otro teléfono" /><div><strong>Scanner alternativo listo</strong><span>{String(Math.floor(segundosVinculo / 60)).padStart(2, '0')}:{String(segundosVinculo % 60).padStart(2, '0')}</span><a href={vinculo.urlTelefono} target="_blank" rel="noreferrer">Abrir enlace</a></div></div>}
                {modo === 'cantidad' ? <>
                  <p className="cuadre-mode-help">1. Confirma el IMEI inicial · 2. Indica la cantidad y presiona Agregar · 3. Revisa la lista y presiona Validar y agregar tira.</p>
                  <div className="cuadre-manual cuadre-quantity-flow">
                    <form onSubmit={confirmarManual}><label className={lecturas.length ? 'validated' : ''}>1. IMEI inicial<div><input value={lecturas[0] ?? entradaManual} onChange={(event) => { if (lecturas.length) limpiarTira(); setEntradaManual(event.target.value) }} inputMode="numeric" placeholder="Ingresa el IMEI inicial" disabled={validando} /><button type="submit" disabled={validando || Boolean(lecturas.length) || !entradaManual}>{lecturas.length ? 'Confirmado' : validando ? 'Validando…' : 'Confirmar'}</button></div>{lecturas.length > 0 && <small>IMEI inicial válido en la base de datos</small>}</label></form>
                    <label>2. Cantidad<div><input type="number" inputMode="numeric" min="1" max="1000" step="1" value={cantidad} onChange={(event) => { setCantidad(event.target.value); setImeisRevision(null) }} onKeyDown={(event) => { if (event.key === 'Enter') { event.preventDefault(); mostrarInformacionTira() } }} placeholder={lecturas.length ? 'Ej.: 500' : 'Confirma primero el IMEI inicial'} disabled={!lecturas.length || validando} /><button type="button" onClick={mostrarInformacionTira} disabled={!lecturas.length || !cantidad || validando}>Agregar</button></div></label>
                  </div>
                </> : <form className="cuadre-manual" onSubmit={confirmarManual}><label>{modo === 'rango' ? lecturas.length ? '2. Último IMEI' : '1. Primer IMEI' : 'IMEI'}<div><input value={entradaManual} onChange={(event) => setEntradaManual(event.target.value)} inputMode="numeric" placeholder="Ingresa el código manualmente" /><button type="submit" disabled={validando || !entradaManual}>Confirmar</button></div></label></form>}
                <div className="cuadre-current"><div><span>TIRA ACTUAL</span><strong>{producto?.producto || 'Selecciona un producto'}</strong></div><b>{imeisRevision ? imeisRevision.length : lecturas.length}</b>{lecturas.length ? <ol>{lecturas.map((imei) => <li key={imei}>{imei}</li>)}</ol> : <p>Esperando lecturas válidas…</p>}
                  {imeisRevision && <div className="order-strip-information"><div><strong>Información de la tira</strong><span>{imeisRevision.length} IMEI listos para agregar</span></div>{imeisRevision.length ? <div className="order-strip-information-list">{imeisRevision.map((imei, index) => <span key={imei}><b>{index + 1}</b><code>{imei}</code><button type="button" onClick={() => setImeisRevision((actuales) => actuales?.filter((actual) => actual !== imei) || null)} aria-label={`Eliminar IMEI ${imei}`}>Eliminar</button></span>)}</div> : <small>Eliminaste todos los IMEI. Limpia la tira para comenzar de nuevo.</small>}</div>}
                  <div className="strip-actions"><button type="button" onClick={limpiarTira} disabled={!lecturas.length}>Limpiar</button>{modo === 'rango' && <button type="button" onClick={mostrarInformacionTira} disabled={!lecturas.length || validando}>Información</button>}<button type="button" onClick={agregarTira} disabled={!lecturas.length || validando || imeisRevision?.length === 0 || (modo === 'cantidad' && !imeisRevision?.length)}>{validando ? 'Validando…' : 'Validar y agregar tira'}</button></div></div>
              </>}
              {error && <div className="scanner-message scanner-message--error">{error}</div>}
            </section>
            <aside className="cuadre-master"><div className="master-list-head"><div><p>PRELIMINAR</p><h3>Lista Master de sobrantes</h3></div><strong>{listaMaster.reduce((total, tira) => total + (tira.modo === 'tigo_money' || tira.modo === 'chip_cantidad' ? tira.cantidadManual : tira.imeis.length), 0)} unidades</strong></div>{!listaMaster.length ? <div className="master-list-empty">Todavía no agregaste tiras.</div> : listaMaster.map((tira) => <article className={`cuadre-master-strip ${tira.modo === 'tigo_money' ? 'cuadre-master-strip--money' : ''}`} key={tira.id}><div><span>{tira.producto}</span><strong>{tira.modo === 'tigo_money' ? `Sobrante · ${integer.format(tira.cantidadManual)} · Efectivización · ${integer.format(tira.cantidadEfectivizada)}` : tira.modo === 'chip_cantidad' ? `Sobrante · ${integer.format(tira.cantidadManual)} de ${integer.format(tira.saldo)}` : `Tira ${tira.numero} · ${tira.imeis.length} unidades`}</strong><small>{tira.modo === 'tigo_money' ? 'TM_Venta + TM_Compra · códigos 0 — 0' : tira.modo === 'chip_cantidad' ? `Por cantidad · ${integer.format(tira.saldo - tira.cantidadManual)} vendidos (los más antiguos)` : `${tira.imeis[0]} — ${tira.imeis.at(-1)}`}</small></div><button type="button" onClick={() => setListaMaster((actual) => actual.filter((item) => item.id !== tira.id))}>Quitar</button></article>)}<label className="cuadre-observation">Observación<textarea maxLength="100" rows="3" value={observacion} onChange={(event) => setObservacion(event.target.value)} placeholder="Observación opcional" /></label><button className="cuadre-finish" type="button" onClick={finalizar} disabled={!listaMaster.length || cargando}>{cargando ? 'Guardando cuadre…' : 'Finalizar cuadre'}</button></aside>
          </div>}
    </section>
  )
}

function Dashboard({ session, saldo, cargandoSaldo, saldoError, onLogout }) {
  const { usuario: currentUser } = session
  const tecnico = currentUser.tecnico
  const [mostrarTodos, setMostrarTodos] = useState(false)
  const [menuMovilAbierto, setMenuMovilAbierto] = useState(false)
  const [pedidoAbierto, setPedidoAbierto] = useState(false)
  const [tiposProducto, setTiposProducto] = useState([])
  const [idTipoProducto, setIdTipoProducto] = useState('')
  const [productosCatalogo, setProductosCatalogo] = useState([])
  const [idProductoPedido, setIdProductoPedido] = useState('')
  const [cantidadPedido, setCantidadPedido] = useState(1)
  const [observacionPedido, setObservacionPedido] = useState('')
  const [detallesPedido, setDetallesPedido] = useState([])
  const [cargandoCatalogo, setCargandoCatalogo] = useState(false)
  const [enviandoPedido, setEnviandoPedido] = useState(false)
  const [pedidoError, setPedidoError] = useState('')
  const [pedidoCreado, setPedidoCreado] = useState(null)
  const [promedioVisible, setPromedioVisible] = useState(false)
  const [promediosVenta, setPromediosVenta] = useState([])
  const [cargandoPromedios, setCargandoPromedios] = useState(false)
  const [promediosError, setPromediosError] = useState('')
  const [vista, setVista] = useState('saldos')
  const [pedidos, setPedidos] = useState([])
  const [cargandoPedidos, setCargandoPedidos] = useState(false)
  const [pedidosError, setPedidosError] = useState('')
  const [pedidoSeleccionado, setPedidoSeleccionado] = useState(null)
  const [detallePedido, setDetallePedido] = useState([])
  const [cargandoDetalle, setCargandoDetalle] = useState(false)
  const [fechaPedidos, setFechaPedidos] = useState('')
  const [tutorialAbierto, setTutorialAbierto] = useState(false)
  const [entidades, setEntidades] = useState([])
  const [depositos, setDepositos] = useState([])
  const [cargandoEntidades, setCargandoEntidades] = useState(false)
  const [cargandoDepositos, setCargandoDepositos] = useState(false)
  const [depositoError, setDepositoError] = useState('')
  const [formularioDeposito, setFormularioDeposito] = useState({
    idEntidad: '',
    cuenta: '',
    monto: '',
    op: ''
  })
  const [enviandoDeposito, setEnviandoDeposito] = useState(false)
  const [depositoCreado, setDepositoCreado] = useState(null)
  const initials = currentUser.nombre.split(/\s+/).slice(0, 2).map((part) => part[0]).join('').toUpperCase()
  const productos = saldo?.productos ?? []
  const productosMovil = mostrarTodos ? productos : productos.slice(0, 5)
  const pedidosFiltrados = fechaPedidos
    ? pedidos.filter((pedido) => pedido.fechaRegistro?.startsWith(fechaPedidos))
    : pedidos
  const fechaHoyPedidos = (() => {
    const fecha = new Date()
    return `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, '0')}-${String(fecha.getDate()).padStart(2, '0')}`
  })()
  const pedidosActualizadosHoy = pedidos.filter((pedido) => pedido.fechaRegistro?.startsWith(fechaHoyPedidos)
    && (pedido.estadoAprobado === 2 || pedido.modificadoPorAlmacen === 1)).length

  useEffect(() => {
    let activo = true
    api('/api/auth/pedidos-en-ruta', { headers: { Authorization: `Bearer ${session.token}` } })
      .then((data) => { if (activo) setPedidos(data) })
      .catch(() => null)
    return () => { activo = false }
  }, [session.token])

  async function abrirPedido() {
    setIdTipoProducto('')
    setProductosCatalogo([])
    setIdProductoPedido('')
    setCantidadPedido(1)
    setObservacionPedido('')
    setDetallesPedido([])
    setPedidoError('')
    setPedidoCreado(null)
    setPromedioVisible(false)
    setPromediosVenta([])
    setPromediosError('')
    setPedidoAbierto(true)
    setCargandoCatalogo(true)
    try {
      const tipos = await api('/api/auth/tipos-producto', { headers: { Authorization: `Bearer ${session.token}` } })
      setTiposProducto(tipos)
    } catch (err) {
      setPedidoError(err.message)
    } finally {
      setCargandoCatalogo(false)
    }
  }

  function cerrarPedido() {
    if (!enviandoPedido) setPedidoAbierto(false)
  }

  async function mostrarPromedioVenta() {
    if (promedioVisible) {
      setPromedioVisible(false)
      return
    }
    setPromedioVisible(true)
    setPromediosError('')
    if (promediosVenta.length) return
    setCargandoPromedios(true)
    try {
      const data = await api('/api/auth/promedio-venta-ruta', { headers: { Authorization: `Bearer ${session.token}` } })
      setPromediosVenta(data)
    } catch (err) {
      setPromediosError(err.message)
    } finally {
      setCargandoPromedios(false)
    }
  }

  async function cambiarTipoProducto(event) {
    const value = event.target.value
    setIdTipoProducto(value)
    setIdProductoPedido('')
    setProductosCatalogo([])
    setPedidoError('')
    if (!value) return
    setCargandoCatalogo(true)
    try {
      const catalogo = await api(`/api/auth/productos?idTipoProducto=${value}`, { headers: { Authorization: `Bearer ${session.token}` } })
      const catalogoVendedor = catalogo.filter((producto) => producto.idProducto !== 32)
      setProductosCatalogo(catalogoVendedor)
      if (catalogoVendedor[0]) setIdProductoPedido(String(catalogoVendedor[0].idProducto))
    } catch (err) {
      setPedidoError(err.message)
    } finally {
      setCargandoCatalogo(false)
    }
  }

  function agregarDetalle() {
    const producto = productosCatalogo.find((item) => item.idProducto === Number(idProductoPedido))
    const cantidad = Number(cantidadPedido)
    if (!producto || !Number.isInteger(cantidad) || cantidad < 1) {
      setPedidoError('Selecciona un producto e ingresa una cantidad válida.')
      return
    }
    if (detallesPedido.some((item) => item.idProducto === producto.idProducto)) {
      setPedidoError('Ese producto ya está agregado al pedido.')
      return
    }
    setDetallesPedido((actuales) => [...actuales, { ...producto, cantidad, totalParcial: producto.precioVenta * cantidad }])
    setCantidadPedido(1)
    setPedidoError('')
  }

  function eliminarDetalle(idProducto) {
    setDetallesPedido((actuales) => actuales.filter((item) => item.idProducto !== idProducto))
  }

  async function guardarPedido(event) {
    event.preventDefault()
    setPedidoError('')
    setEnviandoPedido(true)
    try {
      const creado = await api('/api/auth/pedido-en-ruta', {
        method: 'POST',
        headers: { Authorization: `Bearer ${session.token}` },
        body: JSON.stringify({
          detalles: detallesPedido.map((item) => ({ idProducto: item.idProducto, cantidad: item.cantidad })),
          observacion: observacionPedido.trim(),
        }),
      })
      setPedidoCreado(creado)
    } catch (err) {
      setPedidoError(err.message)
    } finally {
      setEnviandoPedido(false)
    }
  }

  async function mostrarPedidos() {
    setVista('pedidos')
    setPedidosError('')
    setCargandoPedidos(true)
    try {
      const data = await api('/api/auth/pedidos-en-ruta', { headers: { Authorization: `Bearer ${session.token}` } })
      setPedidos(data)
    } catch (err) {
      setPedidosError(err.message)
    } finally {
      setCargandoPedidos(false)
    }
  }

  function hacerPedidoDesdeHistorial() {
    setVista('saldos')
    abrirPedido()
  }

  async function verDetallePedido(pedido) {
    setPedidoSeleccionado(pedido)
    setDetallePedido([])
    setPedidosError('')
    setCargandoDetalle(true)
    try {
      const data = await api(`/api/auth/pedidos-en-ruta/${pedido.idPedido}/detalle`, { headers: { Authorization: `Bearer ${session.token}` } })
      setDetallePedido(data)
    } catch (err) {
      setPedidosError(err.message)
      setPedidoSeleccionado(null)
    } finally {
      setCargandoDetalle(false)
    }
  }

  async function mostrarDepositos() {
    setVista('depositos')
    setDepositoError('')
    
    // Cargar entidades si no están cargadas
    if (entidades.length === 0) {
      setCargandoEntidades(true)
      try {
        const data = await api('/api/auth/entidades', { headers: { Authorization: `Bearer ${session.token}` } })
        setEntidades(data)
      } catch (err) {
        setDepositoError('No se pudieron cargar los bancos: ' + err.message)
      } finally {
        setCargandoEntidades(false)
      }
    }
    
    // Cargar depósitos
    setCargandoDepositos(true)
    try {
      const data = await api('/api/auth/depositos', { headers: { Authorization: `Bearer ${session.token}` } })
      setDepositos(data)
    } catch (err) {
      setDepositoError('No se pudieron cargar los depósitos: ' + err.message)
    } finally {
      setCargandoDepositos(false)
    }
  }

  async function registrarDeposito(event) {
    event.preventDefault()
    setDepositoError('')
    setDepositoCreado(null)
    setEnviandoDeposito(true)
    
    try {
      const response = await api('/api/auth/depositos', {
        method: 'POST',
        headers: { Authorization: `Bearer ${session.token}` },
        body: JSON.stringify({
          idEntidad: parseInt(formularioDeposito.idEntidad),
          cuenta: formularioDeposito.cuenta.trim(),
          monto: parseFloat(formularioDeposito.monto),
          op: formularioDeposito.op.trim() || null
        })
      })
      
      setDepositoCreado(response)
      setFormularioDeposito({ idEntidad: '', cuenta: '', monto: '', op: '' })
      
      // Recargar lista de depósitos
      const data = await api('/api/auth/depositos', { headers: { Authorization: `Bearer ${session.token}` } })
      setDepositos(data)
    } catch (err) {
      setDepositoError(err.message)
    } finally {
      setEnviandoDeposito(false)
    }
  }

  return (
    <main className="dashboard-page">
      <header className="topbar">
        <button className="mobile-menu" type="button" aria-label="Abrir menú" aria-expanded={menuMovilAbierto} onClick={() => setMenuMovilAbierto(true)}><span /><span /><span /></button>
        <div className="topbar-brand" data-tour="tech-brand"><BrandMark /><span>Operaciones Técnicas</span></div>
        <div className="topbar-user">
          <div className="avatar">{initials}</div>
          <div><strong>{currentUser.nombre}</strong><span>{currentUser.sucursal.nombre}</span></div>
          <button type="button" onClick={onLogout}>Cerrar sesión</button>
        </div>
      </header>

      {menuMovilAbierto && (
        <div className="mobile-drawer-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setMenuMovilAbierto(false) }}>
          <aside className="mobile-drawer" aria-label="Menú de usuario">
            <div className="mobile-drawer-head">
              <div className="topbar-brand"><BrandMark /><span>Operaciones Técnicas</span></div>
              <button type="button" aria-label="Cerrar menú" onClick={() => setMenuMovilAbierto(false)}>×</button>
            </div>
            <div className="mobile-drawer-user">
              <div className="avatar">{initials}</div>
              <div><strong>{currentUser.nombre}</strong><span>{currentUser.rol} · {currentUser.sucursal.nombre}</span></div>
            </div>
            <nav className="mobile-drawer-nav">
              <button className={vista === 'saldos' ? 'active' : ''} type="button" onClick={() => { setVista('saldos'); setMenuMovilAbierto(false) }}><span>▦</span> Ver saldos</button>
              <button className={vista === 'pedidos' ? 'active' : ''} type="button" onClick={() => { setMenuMovilAbierto(false); mostrarPedidos() }}><span>▤</span> Ver pedidos {pedidosActualizadosHoy > 0 && <b className="orders-nav-badge">{pedidosActualizadosHoy > 99 ? '99+' : pedidosActualizadosHoy}</b>}</button>
              <button className={vista === 'depositos' ? 'active' : ''} type="button" onClick={() => { setMenuMovilAbierto(false); mostrarDepositos() }}><span>▧</span> Mis depósitos</button>
              <button className={vista === 'cuadre' ? 'active' : ''} type="button" onClick={() => { setVista('cuadre'); setMenuMovilAbierto(false) }}><span>▣</span> Mi Cuadre</button>
              <button type="button" onClick={() => { setMenuMovilAbierto(false); setTutorialAbierto(true) }}><span>?</span> Ver tutorial</button>
            </nav>
            <div className="mobile-drawer-session"><span /><div><strong>Conexión segura</strong><small>JWT activo</small></div></div>
            <button className="mobile-drawer-logout" type="button" onClick={onLogout}><span>↪</span> Cerrar sesión</button>
          </aside>
        </div>
      )}

      <div className="dashboard-shell">
        <aside className="sidebar">
          <p className="sidebar-label">MENÚ PRINCIPAL</p>
          <button className={`nav-item ${vista !== 'cuadre' ? 'nav-item--active' : ''}`} type="button" onClick={() => setVista('saldos')}><span>▦</span> Resumen de ruta</button>
          <button className={`nav-item ${vista === 'cuadre' ? 'nav-item--active' : ''}`} type="button" onClick={() => setVista('cuadre')}><span>▣</span> Mi Cuadre</button>
          <button className="nav-item" type="button"><span>◎</span> Mi perfil</button>
          <button className="nav-item nav-item--tutorial" type="button" onClick={() => setTutorialAbierto(true)}><span>?</span> Ver tutorial</button>
          <div className="sidebar-status"><span />Conexión segura<div>JWT activo</div></div>
        </aside>

        <section className="workspace">
          <div className="workspace-heading">
            {vista === 'cuadre'
              ? <div><p>CONTROL PERSONAL</p><h1>Mi Cuadre</h1><span>Vinculación del scanner para tu sesión de trabajo.</span></div>
              : <div><p>RESUMEN OPERATIVO</p><h1>Saldo de ruta</h1><span>Inventario disponible asignado al técnico.</span></div>}
            <div className="date-chip">Actualizado ahora</div>
          </div>

          {currentUser.idRol !== 1 && !tecnico?.esTecnico ? (
            <div className="empty-state"><div>i</div><h2>No es técnico</h2><p>Este usuario no tiene un registro activo en Usuario Técnico.</p></div>
          ) : !tecnico.idRuta ? (
            <div className="empty-state"><div>!</div><h2>Sin ruta asignada</h2><p>El técnico existe, pero todavía no tiene una ruta activa.</p></div>
          ) : (
            <>
              <section className="identity-strip" data-tour="tech-identity">
                <div className="identity-main"><span className="status-dot" /><div><small>TÉCNICO ACTIVO</small><strong>{tecnico.nombre}<span className="technician-route">{tecnico.nombreRuta}</span></strong></div><span className="identity-chevron">⌃</span></div>
              </section>

              <nav className="route-view-switch" aria-label="Secciones de la ruta" data-tour="tech-sections">
                <button className={vista === 'saldos' ? 'active' : ''} type="button" onClick={() => setVista('saldos')}><span>▦</span> Ver saldos</button>
                <button className={vista === 'pedidos' ? 'active' : ''} type="button" onClick={mostrarPedidos}><span>▤</span> Ver pedidos {pedidosActualizadosHoy > 0 && <b className="orders-nav-badge">{pedidosActualizadosHoy > 99 ? '99+' : pedidosActualizadosHoy}</b>}</button>
                <button className={vista === 'depositos' ? 'active' : ''} type="button" onClick={mostrarDepositos}><span>▧</span> Depósitos</button>
                <button className={vista === 'cuadre' ? 'active' : ''} type="button" onClick={() => setVista('cuadre')}><span>▣</span> Mi Cuadre</button>
              </nav>

              <div hidden={vista !== 'saldos'}>
              {cargandoSaldo ? (
                <div className="loading-panel"><span className="spinner spinner--dark" />Consultando saldo de la ruta…</div>
              ) : saldoError ? (
                <div className="alert-panel"><strong>No se pudo cargar el saldo</strong><span>{saldoError}</span></div>
              ) : (
                <>
                  <section className="metrics">
                    <article><span>Productos con saldo</span><strong>{integer.format(saldo?.totalProductos ?? 0)}</strong><small>Referencias disponibles</small></article>
                    <article><span>Unidades disponibles</span><strong>{integer.format(saldo?.totalUnidades ?? 0)}</strong><small>Existencia total de ruta</small></article>
                  </section>

                  <section className="balance-card" data-tour="tech-balance">
                    <div className="balance-heading">
                      <div><p>DETALLE DE INVENTARIO</p><h2>Saldo disponible</h2></div>
                      <div className="balance-actions">
                        <span>{saldo?.ruta}</span>
                        <button type="button" onClick={abrirPedido}>Hacer pedido</button>
                      </div>
                    </div>
                    <div className="table-wrap">
                      <table>
                        <thead><tr><th>Producto</th><th className="number">Cantidad</th></tr></thead>
                        <tbody>
                          {saldo?.productos?.map((item) => (
                            <tr key={item.idProducto}>
                              <td><div className="product-cell"><strong>{nombreProductoSaldo(item)}</strong></div></td>
                              <td className="number quantity">{integer.format(item.cantidad)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                    <div className="mobile-product-list">
                      {productosMovil.map((item, index) => (
                        <article className="mobile-product" key={item.idProducto}>
                          <div className="mobile-product-head">
                            <span className="product-number">{index + 1}</span>
                            <strong>{nombreProductoSaldo(item)}</strong>
                          </div>
                          <dl>
                            <div><dt>Cantidad</dt><dd>{integer.format(item.cantidad)}</dd></div>
                          </dl>
                        </article>
                      ))}
                      {productos.length > 5 && (
                        <button className="show-all" type="button" onClick={() => setMostrarTodos((value) => !value)}>
                          {mostrarTodos ? 'Ver menos' : `Ver todos (${productos.length})`} <span>{mostrarTodos ? '⌃' : '⌄'}</span>
                        </button>
                      )}
                    </div>
                  </section>

                  {pedidoAbierto && (
                    <div className="order-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) cerrarPedido() }}>
                      <section className="order-dialog" role="dialog" aria-modal="true" aria-labelledby="order-title">
                        <div className="order-dialog-head">
                          <div><p>NUEVO PEDIDO</p><h2 id="order-title">Hacer pedido</h2></div>
                          <button type="button" aria-label="Cerrar" onClick={cerrarPedido}>×</button>
                        </div>

                        {pedidoCreado ? (
                          <div className="order-success">
                            <span>✓</span>
                            <h3>Pedido registrado</h3>
                            <p>El pedido <strong>#{pedidoCreado.idPedido}</strong> fue guardado y está pendiente de aprobación.</p>
                            <dl>
                              <div><dt>Productos</dt><dd>{integer.format(pedidoCreado.cantidadProductos)}</dd></div>
                              <div><dt>Unidades</dt><dd>{integer.format(pedidoCreado.cantidadUnidades)}</dd></div>
                              <div><dt>Total</dt><dd>{money.format(pedidoCreado.total)}</dd></div>
                            </dl>
                            <button type="button" onClick={cerrarPedido}>Aceptar</button>
                          </div>
                        ) : (
                          <form className="order-form" onSubmit={guardarPedido}>
                            <div className="order-form-intro">
                              <p>Arma el pedido para <strong>{tecnico.nombreRuta}</strong>. Primero selecciona el tipo; los productos se cargan desde <strong>tbl_Producto</strong>.</p>
                              <button type="button" onClick={mostrarPromedioVenta}>{promedioVisible ? 'Ocultar promedio' : 'Ver promedio de venta'}</button>
                            </div>
                            {promedioVisible && (
                              <section className="sales-average-panel">
                                <div className="sales-average-head"><div><span>REFERENCIA DE PEDIDO</span><strong>Promedio de venta de la ruta</strong></div><small>Mismo día de la semana del mes anterior</small></div>
                                {cargandoPromedios ? <div className="sales-average-message">Calculando promedio…</div>
                                  : promediosError ? <div className="sales-average-message error">{promediosError}</div>
                                    : promediosVenta.length === 0 ? <div className="sales-average-message">No existen ventas históricas suficientes para esta ruta.</div>
                                      : <div className="sales-average-table"><div className="sales-average-row head"><span>Producto</span><span>Promedio</span><span>Diferencia</span></div>{promediosVenta.map((item) => { const diferencia = Number(item.diferencia); return <div className="sales-average-row" key={item.idProducto}><strong>{item.producto}</strong><span>{item.promedioVenta}</span><b className={diferencia < 0 ? 'negative' : 'positive'}>{item.diferencia}</b></div> })}</div>}
                                <p>La diferencia es promedio histórico menos saldo actual. Positivo: está por debajo del promedio; negativo: está por encima. Es solo informativo.</p>
                              </section>
                            )}
                            <div className="order-entry-grid">
                              <div>
                                <label htmlFor="pedido-tipo">Tipo de producto</label>
                                <select id="pedido-tipo" value={idTipoProducto} onChange={cambiarTipoProducto} disabled={cargandoCatalogo} required>
                                  <option value="">Seleccionar tipo</option>
                                  {tiposProducto.map((tipo) => <option key={tipo.idTipoProducto} value={tipo.idTipoProducto}>{tipo.nombre}</option>)}
                                </select>
                              </div>
                              <div>
                                <label htmlFor="pedido-producto">Producto</label>
                                <select id="pedido-producto" value={idProductoPedido} onChange={(event) => setIdProductoPedido(event.target.value)} disabled={!idTipoProducto || cargandoCatalogo} required>
                                  {!productosCatalogo.length && <option value="">Sin productos</option>}
                                  {productosCatalogo.map((item) => <option key={item.idProducto} value={item.idProducto}>{item.nombre}</option>)}
                                </select>
                              </div>
                              <div className="order-quantity">
                                <label htmlFor="pedido-cantidad">Cantidad</label>
                                <input id="pedido-cantidad" type="number" min="1" step="1" value={cantidadPedido} onChange={(event) => setCantidadPedido(event.target.value)} required />
                              </div>
                              <button className="add-detail" type="button" onClick={agregarDetalle} disabled={!idProductoPedido}>Agregar</button>
                            </div>

                            <div className="order-observation">
                              <label htmlFor="pedido-observacion">Observación del pedido <span>Opcional</span></label>
                              <textarea id="pedido-observacion" maxLength="50" rows="3" value={observacionPedido} onChange={(event) => setObservacionPedido(event.target.value)} placeholder="Ej.: Reposición por alta demanda de la ruta" />
                              <small>{observacionPedido.length}/50 caracteres</small>
                            </div>

                            <div className="order-lines">
                              <div className="order-lines-title"><strong>Detalle del pedido</strong><span>{detallesPedido.length} producto(s)</span></div>
                              {detallesPedido.length === 0 ? (
                                <div className="order-lines-empty">Agrega productos para formar el pedido.</div>
                              ) : (
                                <div className="order-lines-table">
                                  <div className="order-line order-line--head"><span>Producto</span><span>Cant.</span><span>Precio</span><span>Subtotal</span><span /></div>
                                  {detallesPedido.map((item) => (
                                    <div className="order-line" key={item.idProducto}>
                                      <strong>{item.nombre}</strong>
                                      <span>{integer.format(item.cantidad)}</span>
                                      <span>{money.format(item.precioVenta)}</span>
                                      <span>{money.format(item.totalParcial)}</span>
                                      <button type="button" aria-label={`Quitar ${item.nombre}`} onClick={() => eliminarDetalle(item.idProducto)}>×</button>
                                    </div>
                                  ))}
                                  <div className="order-total"><span>Total del pedido</span><strong>{money.format(detallesPedido.reduce((total, item) => total + item.totalParcial, 0))}</strong></div>
                                </div>
                              )}
                            </div>
                            {pedidoError && <div className="order-error">{pedidoError}</div>}
                            <div className="order-form-actions">
                              <button type="button" onClick={cerrarPedido} disabled={enviandoPedido}>Cancelar</button>
                              <button type="submit" disabled={enviandoPedido || detallesPedido.length === 0}>
                                {enviandoPedido ? 'Guardando…' : 'Confirmar pedido'}
                              </button>
                            </div>
                          </form>
                        )}
                      </section>
                    </div>
                  )}
                </>
              )}
              </div>

              {vista === 'pedidos' && (
                <section className="orders-card">
                  <div className="orders-heading">
                    <div className="orders-title-row">
                      <div><p>HISTORIAL DE SOLICITUDES</p><h2>Mis pedidos</h2></div>
                      <button className="new-order-from-history" type="button" onClick={hacerPedidoDesdeHistorial}>Hacer pedido</button>
                    </div>
                    <div className="orders-tools">
                      <label htmlFor="fecha-pedidos">Fecha</label>
                      <input id="fecha-pedidos" type="date" value={fechaPedidos} onChange={(event) => setFechaPedidos(event.target.value)} />
                      {fechaPedidos && <button className="clear-date" type="button" onClick={() => setFechaPedidos('')}>Limpiar</button>}
                    </div>
                  </div>
                  {cargandoPedidos ? (
                    <div className="orders-message">Consultando pedidos…</div>
                  ) : pedidosError ? (
                    <div className="orders-message orders-message--error">{pedidosError}</div>
                  ) : pedidosFiltrados.length === 0 ? (
                    <div className="orders-message">{fechaPedidos ? 'No hay pedidos registrados en esa fecha.' : 'Todavía no tienes pedidos registrados.'}</div>
                  ) : (
                    <div className="orders-list">
                      <div className="orders-result-count">{pedidosFiltrados.length} pedido(s) encontrado(s)</div>
                      {pedidosFiltrados.map((pedido) => {
                        const modificado = pedido.modificadoPorAlmacen === 1
                        const aprobado = pedido.estadoAprobado === 2
                        return <article className={`order-summary ${modificado || aprobado ? 'order-summary--updated' : ''}`} key={pedido.idPedido}>
                          <div className="order-summary-main">
                            <span className="order-number">#{pedido.idPedido}</span>
                            <div><strong>Pedido {pedido.idPedido}</strong><small>{dateTime.format(new Date(pedido.fechaRegistro))}</small></div>
                          </div>
                          <dl>
                            <div><dt>Productos</dt><dd>{pedido.cantidadProductos}</dd></div>
                            <div><dt>Unidades</dt><dd>{pedido.cantidadUnidades}</dd></div>
                            <div><dt>Total</dt><dd>{money.format(pedido.total)}</dd></div>
                          </dl>
                          <span className={`order-status order-status--${aprobado ? 'approved' : 'pending'}`}>{aprobado ? 'Aprobado' : 'Pendiente'}</span>
                          <button className="view-detail" type="button" onClick={() => verDetallePedido(pedido)}>Ver detalle</button>
                          {(modificado || aprobado) && <div className={`order-update-message ${modificado ? 'modified' : 'approved'}`}><span>{modificado ? '!' : '✓'}</span><div><small>{modificado && aprobado ? 'PEDIDO MODIFICADO Y APROBADO' : modificado ? 'ALMACÉN MODIFICÓ TU PEDIDO' : 'PEDIDO APROBADO POR ALMACÉN'}</small><strong>{modificado ? pedido.comentarioAlmacen : 'El pedido fue confirmado y se encuentra listo para la fecha de entrega.'}</strong></div></div>}
                        </article>
                      })}
                    </div>
                  )}
                </section>
              )}

              {vista === 'depositos' && (
                <section className="orders-card">
                  <div className="orders-heading">
                    <div><p>REGISTRO DE DEPÓSITOS</p><h2>Mis depósitos</h2></div>
                  </div>
                  
                  {depositoCreado && (
                    <div className="orders-message orders-message--success">
                      ✓ {depositoCreado.mensaje}
                    </div>
                  )}
                  
                  {depositoError && (
                    <div className="orders-message orders-message--error">
                      {depositoError}
                    </div>
                  )}

                  <form className="order-form deposit-form" onSubmit={registrarDeposito}>
                    <div className="order-form-intro deposit-form-intro">
                      <p>Registra el depósito bancario para la ruta activa. El estado se guarda como <strong>pendiente</strong> para aprobación de almacén.</p>
                    </div>

                    <div className="deposit-entry-grid">
                      <div>
                        <label htmlFor="deposito-entidad">Banco</label>
                        <select
                          id="deposito-entidad"
                          value={formularioDeposito.idEntidad}
                          onChange={(e) => setFormularioDeposito({ ...formularioDeposito, idEntidad: e.target.value })}
                          required
                          disabled={cargandoEntidades || enviandoDeposito}
                        >
                          <option value="">Seleccione un banco</option>
                          {entidades.map((entidad) => (
                            <option key={entidad.idEntidad} value={entidad.idEntidad}>
                              {entidad.nombre}
                            </option>
                          ))}
                        </select>
                      </div>

                      <div>
                        <label htmlFor="deposito-cuenta">Cuenta</label>
                        <input
                          id="deposito-cuenta"
                          type="text"
                          value={formularioDeposito.cuenta}
                          onChange={(e) => setFormularioDeposito({ ...formularioDeposito, cuenta: e.target.value })}
                          placeholder="Número de cuenta"
                          required
                          maxLength="50"
                          disabled={enviandoDeposito}
                        />
                      </div>

                      <div>
                        <label htmlFor="deposito-monto">Monto</label>
                        <input
                          id="deposito-monto"
                          type="number"
                          value={formularioDeposito.monto}
                          onChange={(e) => setFormularioDeposito({ ...formularioDeposito, monto: e.target.value })}
                          placeholder="0.00"
                          required
                          min="0.01"
                          step="0.01"
                          disabled={enviandoDeposito}
                        />
                      </div>

                      <div>
                        <label htmlFor="deposito-op">OP (opcional)</label>
                        <input
                          id="deposito-op"
                          type="text"
                          value={formularioDeposito.op}
                          onChange={(e) => setFormularioDeposito({ ...formularioDeposito, op: e.target.value })}
                          placeholder="Número de operación"
                          maxLength="50"
                          disabled={enviandoDeposito}
                        />
                      </div>

                      <button className="add-detail deposit-submit" type="submit" disabled={enviandoDeposito || cargandoEntidades}>
                        {enviandoDeposito ? 'Registrando...' : 'Registrar depósito'}
                      </button>
                    </div>
                  </form>

                  {cargandoDepositos ? (
                    <div className="orders-message">Cargando depósitos…</div>
                  ) : depositos.length === 0 ? (
                    <div className="orders-message">No hay depósitos registrados.</div>
                  ) : (
                    <div className="orders-list deposit-list">
                      <div className="orders-result-count">{depositos.length} depósito(s) registrado(s)</div>
                      {depositos.map((deposito) => (
                        <article className="order-summary deposit-summary" key={deposito.idDeposito}>
                          <div className="order-summary-main">
                            <span className="order-number">#{deposito.idDeposito}</span>
                            <div>
                              <strong>{deposito.nombreBanco}</strong>
                              <small>{new Date(deposito.fechaRegistro).toLocaleString('es-BO')}</small>
                            </div>
                          </div>
                          <dl>
                            <div><dt>Cuenta</dt><dd>{deposito.cuenta}</dd></div>
                            <div><dt>Monto</dt><dd>{money.format(deposito.monto)}</dd></div>
                            <div><dt>OP</dt><dd>{deposito.op || 'Sin OP'}</dd></div>
                          </dl>
                          <div>
                            <span className={`order-status order-status--${deposito.estadoAprobacion === 3 ? 'approved' : deposito.estadoAprobacion === 1 ? 'rejected' : 'pending'}`}>
                              {deposito.estadoTexto}
                            </span>
                          </div>
                        </article>
                      ))}
                    </div>
                  )}
                </section>
              )}

              {vista === 'cuadre' && <MyCuadrePanel session={session} />}

              {(pedidoSeleccionado || cargandoDetalle) && (
                <div className="order-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !cargandoDetalle) setPedidoSeleccionado(null) }}>
                  <section className="order-dialog detail-dialog" role="dialog" aria-modal="true" aria-labelledby="detail-title">
                    <div className="order-dialog-head">
                      <div><p>DETALLE DEL PEDIDO</p><h2 id="detail-title">Pedido #{pedidoSeleccionado?.idPedido}</h2></div>
                      <button type="button" aria-label="Cerrar" onClick={() => setPedidoSeleccionado(null)}>×</button>
                    </div>
                    {cargandoDetalle ? (
                      <div className="orders-message">Consultando detalle…</div>
                    ) : (
                      <div className="detail-content">
                        <div className="detail-meta">
                          <span>{dateTime.format(new Date(pedidoSeleccionado.fechaRegistro))}</span>
                          <strong>{money.format(pedidoSeleccionado.total)}</strong>
                        </div>
                        <div className="detail-observation"><span>Observación</span><strong>{pedidoSeleccionado.observacion || 'Sin observación'}</strong></div>
                        {pedidoSeleccionado.modificadoPorAlmacen === 1 && <div className="warehouse-change-notice"><span>MODIFICADO POR ALMACÉN</span><strong>{pedidoSeleccionado.comentarioAlmacen}</strong></div>}
                        <div className="detail-table">
                          <div className="detail-row detail-row--head"><span>Producto</span><span>Tipo</span><span>Cant.</span><span>Precio</span><span>Subtotal</span></div>
                          {detallePedido.map((detalle) => (
                            <div className="detail-row" key={detalle.idDetalle}>
                              <strong>{detalle.producto}</strong><span>{detalle.tipoProducto || 'Sin tipo'}</span><span>{detalle.cantidad}</span><span>{money.format(detalle.precio)}</span><span>{money.format(detalle.totalParcial)}</span>
                            </div>
                          ))}
                        </div>
                        <button className="detail-close" type="button" onClick={() => setPedidoSeleccionado(null)}>Cerrar</button>
                      </div>
                    )}
                  </section>
                </div>
              )}
            </>
          )}
        </section>
      </div>
      {tutorialAbierto && <GuidedTour onClose={() => setTutorialAbierto(false)} steps={[
        { target: '[data-tour="tech-brand"]', title: 'Bienvenido a Operaciones Técnicas', description: 'Este recorrido te mostrará las funciones principales. El tutorial solo señala elementos: no guarda pedidos, no cambia saldos y no realiza cuadres.' },
        { target: '[data-tour="tech-identity"]', title: 'Tu identidad y ruta', description: 'Aquí confirmas con qué técnico y ruta estás trabajando antes de realizar cualquier operación.' },
        { target: '[data-tour="tech-sections"]', title: 'Pedidos de tu ruta', description: 'Este mock permite practicar cómo se ven pedidos por filtros (hoy/histórico) sin tocar datos reales.', mock: 'tech-orders' },
        { target: '[data-tour="tech-sections"]', title: 'Detalle del pedido', description: 'Aquí practicas la lectura del detalle y la alerta de modificación por almacén.', mock: 'tech-detail' },
        { target: '[data-tour="tech-balance"]', title: 'Saldo disponible', description: 'Consulta las cantidades asignadas a tu ruta. Desde esta sección también puedes comenzar un nuevo pedido.' },
        { target: '[data-tour="tech-sections"]', title: 'Mi Cuadre preliminar', description: 'Simula el envío del cuadre del vendedor. Es una capacitación: no actualiza inventario ni estados reales.', mock: 'tech-cashup' },
      ]} />}
    </main>
  )
}

function WarehouseStatisticsPanelLegacy({ session }) {
  const hoy = new Date().toISOString().slice(0, 10)
  const inicioMes = `${hoy.slice(0, 7)}-01`
  const [fechaDesdeInput, setFechaDesdeInput] = useState(inicioMes)
  const [fechaHastaInput, setFechaHastaInput] = useState(hoy)
  const [rango, setRango] = useState({ desde: inicioMes, hasta: hoy })
  const [datos, setDatos] = useState([])
  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    setCargando(true)
    setError('')
    api(`/api/auth/almacen/estadisticas?fechaDesde=${rango.desde}&fechaHasta=${rango.hasta}`, {
      headers: { Authorization: `Bearer ${session.token}` },
    }).then((respuesta) => { if (active) setDatos(respuesta) })
      .catch((err) => { if (active) setError(err.message) })
      .finally(() => { if (active) setCargando(false) })
    return () => { active = false }
  }, [session.token, rango])

  const dias = []
  const cursor = new Date(`${rango.desde}T00:00:00`)
  const fin = new Date(`${rango.hasta}T00:00:00`)
  while (cursor <= fin) {
    dias.push(cursor.toISOString().slice(0, 10))
    cursor.setDate(cursor.getDate() + 1)
  }
  const porDia = new Map(dias.map((fecha) => [fecha, { fecha, realizados: 0, aprobados: 0, modificados: 0 }]))
  const porRuta = new Map()
  datos.forEach((item) => {
    const fecha = item.fecha
    const dia = porDia.get(fecha) || { fecha, realizados: 0, aprobados: 0, modificados: 0 }
    dia.realizados += item.realizados
    dia.aprobados += item.aprobados
    dia.modificados += item.modificados
    porDia.set(fecha, dia)
    const ruta = porRuta.get(item.idRuta) || { idRuta: item.idRuta, ruta: item.ruta, realizados: 0, aprobados: 0, modificados: 0 }
    ruta.realizados += item.realizados
    ruta.aprobados += item.aprobados
    ruta.modificados += item.modificados
    porRuta.set(item.idRuta, ruta)
  })
  const serieDias = [...porDia.values()].sort((a, b) => a.fecha.localeCompare(b.fecha))
  const serieRutas = [...porRuta.values()].sort((a, b) => (b.realizados + b.aprobados + b.modificados) - (a.realizados + a.aprobados + a.modificados))
  const totales = datos.reduce((total, item) => ({
    realizados: total.realizados + item.realizados,
    aprobados: total.aprobados + item.aprobados,
    modificados: total.modificados + item.modificados,
  }), { realizados: 0, aprobados: 0, modificados: 0 })
  const maxDia = Math.max(1, ...serieDias.flatMap((item) => [item.realizados, item.aprobados, item.modificados]))
  const maxRuta = Math.max(1, ...serieRutas.flatMap((item) => [item.realizados, item.aprobados, item.modificados]))
  const fechaCorta = (fecha) => new Intl.DateTimeFormat('es-BO', { day: '2-digit', month: 'short' }).format(new Date(`${fecha}T00:00:00`))

  function aplicarRango(event) {
    event.preventDefault()
    if (!fechaDesdeInput || !fechaHastaInput || fechaDesdeInput > fechaHastaInput) {
      setError('Selecciona un rango de fechas válido.')
      return
    }
    setRango({ desde: fechaDesdeInput, hasta: fechaHastaInput })
  }

  function usarRango(desde, hasta) {
    setFechaDesdeInput(desde)
    setFechaHastaInput(hasta)
    setRango({ desde, hasta })
  }

  function ultimosTreintaDias() {
    const fecha = new Date(`${hoy}T00:00:00`)
    fecha.setDate(fecha.getDate() - 29)
    usarRango(fecha.toISOString().slice(0, 10), hoy)
  }

  return (
    <section className="warehouse-statistics">
      <header className="statistics-heading">
        <div><p>ANÁLISIS OPERATIVO</p><h2>Estadísticas de pedidos</h2><span>Seguimiento diario y por ruta de las solicitudes de almacén.</span></div>
        <form onSubmit={aplicarRango}>
          <label>Desde<input type="date" value={fechaDesdeInput} max={fechaHastaInput} onChange={(event) => setFechaDesdeInput(event.target.value)} /></label>
          <label>Hasta<input type="date" value={fechaHastaInput} min={fechaDesdeInput} max={hoy} onChange={(event) => setFechaHastaInput(event.target.value)} /></label>
          <button type="submit">Actualizar</button>
        </form>
      </header>
      <div className="statistics-shortcuts">
        <button type="button" onClick={() => usarRango(hoy, hoy)}>Hoy</button>
        <button type="button" onClick={() => usarRango(inicioMes, hoy)}>Este mes</button>
        <button type="button" onClick={ultimosTreintaDias}>Últimos 30 días</button>
        <span>{fechaCorta(rango.desde)} — {fechaCorta(rango.hasta)}</span>
      </div>
      {cargando ? <div className="statistics-message">Consultando estadísticas…</div>
        : error ? <div className="statistics-message error">{error}</div>
          : <>
            <div className="statistics-kpis">
              <article className="created"><span>Pedidos realizados</span><strong>{integer.format(totales.realizados)}</strong><small>Solicitudes creadas en el periodo</small></article>
              <article className="approved"><span>Pedidos aprobados</span><strong>{integer.format(totales.aprobados)}</strong><small>Aprobaciones efectivas de almacén</small></article>
              <article className="modified"><span>Pedidos modificados</span><strong>{integer.format(totales.modificados)}</strong><small>Ajustes registrados por almacén</small></article>
            </div>
            <section className="statistics-card daily-statistics">
              <div className="statistics-card-head"><div><p>COMPORTAMIENTO DIARIO</p><h3>Pedidos por día</h3></div><div className="statistics-legend"><span className="created">Realizados</span><span className="approved">Aprobados</span><span className="modified">Modificados</span></div></div>
              <div className="statistics-chart-scroll">
                <div className="daily-chart" style={{ minWidth: `${Math.max(680, serieDias.length * 54)}px` }}>
                  {serieDias.map((item) => <div className="daily-column" key={item.fecha} title={`${item.fecha}: ${item.realizados} realizados, ${item.aprobados} aprobados, ${item.modificados} modificados`}>
                    <div className="daily-values"><span>{item.realizados || ''}</span><span>{item.aprobados || ''}</span><span>{item.modificados || ''}</span></div>
                    <div className="daily-bars"><i className="created" style={{ height: `${item.realizados ? Math.max(5, item.realizados * 100 / maxDia) : 0}%` }} /><i className="approved" style={{ height: `${item.aprobados ? Math.max(5, item.aprobados * 100 / maxDia) : 0}%` }} /><i className="modified" style={{ height: `${item.modificados ? Math.max(5, item.modificados * 100 / maxDia) : 0}%` }} /></div>
                    <small>{fechaCorta(item.fecha)}</small>
                  </div>)}
                </div>
              </div>
            </section>
            <section className="statistics-card route-statistics">
              <div className="statistics-card-head"><div><p>DISTRIBUCIÓN OPERATIVA</p><h3>Pedidos por ruta</h3></div><span>{serieRutas.length} ruta(s) con movimiento</span></div>
              {serieRutas.length === 0 ? <div className="statistics-message">No existen pedidos en el periodo seleccionado.</div> : <div className="route-statistics-list">
                <div className="route-statistics-row head"><span>Ruta</span><span>Realizados</span><span>Aprobados</span><span>Modificados</span></div>
                {serieRutas.map((item) => <div className="route-statistics-row" key={item.idRuta}>
                  <strong>{item.ruta}</strong>
                  <div><span style={{ width: `${item.realizados * 100 / maxRuta}%` }} /><b>{item.realizados}</b></div>
                  <div><span style={{ width: `${item.aprobados * 100 / maxRuta}%` }} /><b>{item.aprobados}</b></div>
                  <div><span style={{ width: `${item.modificados * 100 / maxRuta}%` }} /><b>{item.modificados}</b></div>
                </div>)}
              </div>}
            </section>
          </>}
    </section>
  )
}

function WarehouseStatisticsPanel({ session }) {
  const hoy = new Date().toISOString().slice(0, 10)
  const inicioMes = `${hoy.slice(0, 7)}-01`
  const [entradas, setEntradas] = useState({ desde: inicioMes, hasta: hoy })
  const [rango, setRango] = useState({ desde: inicioMes, hasta: hoy })
  const [datos, setDatos] = useState([])
  const [detalle, setDetalle] = useState([])
  const [vendedores, setVendedores] = useState([])
  const [consumoDiario, setConsumoDiario] = useState([])
  const [datosAnteriores, setDatosAnteriores] = useState([])
  const [detalleAnterior, setDetalleAnterior] = useState([])
  const [vendedoresAnteriores, setVendedoresAnteriores] = useState([])
  const [consumoAnterior, setConsumoAnterior] = useState([])
  const [demorasCaja, setDemorasCaja] = useState([])
  const [demorasCajaAnteriores, setDemorasCajaAnteriores] = useState([])
  const [vista, setVista] = useState('resumen')
  const [busqueda, setBusqueda] = useState('')
  const [orden, setOrden] = useState({ campo: 'fecha', direccion: 'desc' })
  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState('')
  const campos = ['realizados', 'aprobados', 'pendientes', 'modificados', 'unidadesSolicitadas', 'unidadesAprobadas', 'montoSolicitado', 'montoAprobado', 'cuadresEnviados', 'cuadresRealizados', 'cuadresPendientes', 'cuadresModificados', 'unidadesSobrantes', 'unidadesVendidas', 'montoVendido']
  const vacio = (extra = {}) => Object.assign(Object.fromEntries(campos.map((campo) => [campo, 0])), extra)
  const desplazarMes = (iso, cantidad) => {
    const [anio, mes, dia] = iso.split('-').map(Number)
    const destino = new Date(anio, mes - 1 + cantidad, 1, 12)
    const ultimoDia = new Date(destino.getFullYear(), destino.getMonth() + 1, 0, 12).getDate()
    destino.setDate(Math.min(dia, ultimoDia))
    return `${destino.getFullYear()}-${String(destino.getMonth() + 1).padStart(2, '0')}-${String(destino.getDate()).padStart(2, '0')}`
  }
  const rangoAnterior = { desde: desplazarMes(rango.desde, -1), hasta: desplazarMes(rango.hasta, -1) }

  useEffect(() => {
    let activo = true
    setCargando(true); setError('')
    const headers = { Authorization: `Bearer ${session.token}` }
    Promise.all([
      api(`/api/auth/almacen/estadisticas?fechaDesde=${rango.desde}&fechaHasta=${rango.hasta}`, { headers }),
      api(`/api/auth/almacen/estadisticas/cuadres-detalle?fechaDesde=${rango.desde}&fechaHasta=${rango.hasta}`, { headers }),
      api(`/api/auth/almacen/estadisticas/vendedores?fechaDesde=${rango.desde}&fechaHasta=${rango.hasta}`, { headers }),
      api(`/api/auth/almacen/estadisticas/consumo-productos?fechaDesde=${rango.desde}&fechaHasta=${rango.hasta}`, { headers }),
      api(`/api/auth/almacen/estadisticas?fechaDesde=${rangoAnterior.desde}&fechaHasta=${rangoAnterior.hasta}`, { headers }),
      api(`/api/auth/almacen/estadisticas/cuadres-detalle?fechaDesde=${rangoAnterior.desde}&fechaHasta=${rangoAnterior.hasta}`, { headers }),
      api(`/api/auth/almacen/estadisticas/vendedores?fechaDesde=${rangoAnterior.desde}&fechaHasta=${rangoAnterior.hasta}`, { headers }),
      api(`/api/auth/almacen/estadisticas/consumo-productos?fechaDesde=${rangoAnterior.desde}&fechaHasta=${rangoAnterior.hasta}`, { headers }),
      api(`/api/auth/almacen/estadisticas/demoras-caja?fechaDesde=${rango.desde}&fechaHasta=${rango.hasta}`, { headers }),
      api(`/api/auth/almacen/estadisticas/demoras-caja?fechaDesde=${rangoAnterior.desde}&fechaHasta=${rangoAnterior.hasta}`, { headers }),
    ]).then(([resumen, productos, rankingVendedores, consumo, resumenAnterior, productosAnterior, rankingAnterior, consumoMesAnterior, demoras, demorasAnteriores]) => {
      if (activo) {
        setDatos(resumen); setDetalle(productos); setVendedores(rankingVendedores); setConsumoDiario(consumo)
        setDatosAnteriores(resumenAnterior); setDetalleAnterior(productosAnterior); setVendedoresAnteriores(rankingAnterior); setConsumoAnterior(consumoMesAnterior)
        setDemorasCaja(demoras); setDemorasCajaAnteriores(demorasAnteriores)
      }
    })
      .catch((err) => { if (activo) setError(err.message) })
      .finally(() => { if (activo) setCargando(false) })
    return () => { activo = false }
  }, [session.token, rango])

  const sumar = (destino, origen) => campos.forEach((campo) => { destino[campo] += Number(origen[campo] || 0) })
  const totales = datos.reduce((total, item) => { sumar(total, item); return total }, vacio())
  const totalesAnteriores = datosAnteriores.reduce((total, item) => { sumar(total, item); return total }, vacio())
  const porDia = new Map(); const porRuta = new Map()
  datos.forEach((item) => {
    const dia = porDia.get(item.fecha) || vacio({ fecha: item.fecha }); sumar(dia, item); porDia.set(item.fecha, dia)
    const ruta = porRuta.get(item.idRuta) || vacio({ idRuta: item.idRuta, ruta: item.ruta }); sumar(ruta, item); porRuta.set(item.idRuta, ruta)
  })
  const dias = [...porDia.values()]
  const rutas = [...porRuta.values()]
  const productosMap = new Map()
  detalle.forEach((item) => {
    const actual = productosMap.get(item.idProducto) || { idProducto: item.idProducto, producto: item.producto, tipoProducto: item.tipoProducto, rutas: new Set(), cuadres: new Set(), sobrantes: 0, vendidos: 0, totalVendido: 0 }
    actual.rutas.add(item.idRuta); actual.cuadres.add(item.idCuadre); actual.sobrantes += Number(item.sobrantes || 0); actual.vendidos += Number(item.vendidos || 0); actual.totalVendido += Number(item.totalVendido || 0)
    productosMap.set(item.idProducto, actual)
  })
  const productos = [...productosMap.values()].map((item) => ({ ...item, cantidadRutas: item.rutas.size, cantidadCuadres: item.cuadres.size }))
  const vendedoresOrdenados = [...vendedores].map((item) => ({ ...item, montoSolicitado: Number(item.montoSolicitado || 0) })).sort((a, b) => b.pedidos - a.pedidos || b.unidadesSolicitadas - a.unidadesSolicitadas)
  const rutasOrdenadas = [...rutas].sort((a, b) => b.realizados - a.realizados || b.unidadesSolicitadas - a.unidadesSolicitadas)
  const productosConsumoMap = new Map()
  consumoDiario.forEach((item) => {
    const actual = productosConsumoMap.get(item.idProducto) || { idProducto: item.idProducto, producto: item.producto, tipoProducto: item.tipoProducto, vendidos: 0, sobrantes: 0, totalVendido: 0, dias: new Set(), cuadres: 0 }
    actual.vendidos += Number(item.unidadesVendidas || 0); actual.sobrantes += Number(item.unidadesSobrantes || 0); actual.totalVendido += Number(item.totalVendido || 0); actual.cuadres += Number(item.cuadres || 0)
    if (Number(item.unidadesVendidas || 0) > 0) actual.dias.add(item.fecha)
    productosConsumoMap.set(item.idProducto, actual)
  })
  const fechaInicio = new Date(`${rango.desde}T00:00:00`); const fechaFin = new Date(`${rango.hasta}T00:00:00`)
  const diasPeriodo = Math.max(1, Math.round((fechaFin - fechaInicio) / 86400000) + 1)
  const productosConsumo = [...productosConsumoMap.values()].map((item) => ({ ...item, diasConVenta: item.dias.size, promedioDiario: item.vendidos / diasPeriodo, promedioDiaActivo: item.dias.size ? item.vendidos / item.dias.size : 0, frecuencia: item.dias.size * 100 / diasPeriodo })).sort((a, b) => b.vendidos - a.vendidos)
  const diasPorMes = new Map()
  for (let fecha = new Date(fechaInicio); fecha <= fechaFin; fecha.setDate(fecha.getDate() + 1)) { const clave = fecha.toISOString().slice(0, 7); diasPorMes.set(clave, (diasPorMes.get(clave) || 0) + 1) }
  const mensualMap = new Map()
  consumoDiario.forEach((item) => {
    const mes = item.fecha.slice(0, 7); const clave = `${mes}-${item.idProducto}`
    const actual = mensualMap.get(clave) || { mes, idProducto: item.idProducto, producto: item.producto, tipoProducto: item.tipoProducto, vendidos: 0, sobrantes: 0, totalVendido: 0, dias: new Set(), cuadres: 0 }
    actual.vendidos += Number(item.unidadesVendidas || 0); actual.sobrantes += Number(item.unidadesSobrantes || 0); actual.totalVendido += Number(item.totalVendido || 0); actual.cuadres += Number(item.cuadres || 0)
    if (Number(item.unidadesVendidas || 0) > 0) actual.dias.add(item.fecha)
    mensualMap.set(clave, actual)
  })
  const consumoMensual = [...mensualMap.values()].map((item) => { const diasMes = diasPorMes.get(item.mes) || 1; return { ...item, diasConVenta: item.dias.size, promedioDiario: item.vendidos / diasMes, promedioDiaActivo: item.dias.size ? item.vendidos / item.dias.size : 0, frecuencia: item.dias.size * 100 / diasMes } })
  const vendedorTop = vendedoresOrdenados[0]
  const rutaTop = rutasOrdenadas[0]
  const tarjetaTop = productosConsumo.filter((item) => String(item.tipoProducto).toLowerCase().includes('tarjeta'))[0]
  const productoTop = productosConsumo[0]
  const coincide = (item) => !busqueda.trim() || `${item.ruta || ''} ${item.vendedor || ''} ${item.producto || ''} ${item.tipoProducto || ''} ${item.mes || ''} ${item.idRuta || ''} ${item.idCuadre || ''}`.toLowerCase().includes(busqueda.trim().toLowerCase())
  const ordenar = (filas) => [...filas].filter(coincide).sort((a, b) => {
    const ai = a[orden.campo] ?? ''; const bi = b[orden.campo] ?? ''
    const comparacion = typeof ai === 'number' || typeof bi === 'number' ? Number(ai) - Number(bi) : String(ai).localeCompare(String(bi))
    return orden.direccion === 'asc' ? comparacion : -comparacion
  })
  const cambiarOrden = (campo) => setOrden((actual) => ({ campo, direccion: actual.campo === campo && actual.direccion === 'desc' ? 'asc' : 'desc' }))
  const encabezado = (campo, texto) => <button type="button" onClick={() => cambiarOrden(campo)}>{texto}<span>{orden.campo === campo ? (orden.direccion === 'asc' ? '▲' : '▼') : '↕'}</span></button>
  const fechaCorta = (fecha) => new Intl.DateTimeFormat('es-BO', { day: '2-digit', month: 'short', year: '2-digit' }).format(new Date(`${fecha}T00:00:00`))
  const maxDia = Math.max(1, ...dias.flatMap((item) => [item.realizados, item.aprobados, item.cuadresRealizados]))
  const usarRango = (desde, hasta) => { setEntradas({ desde, hasta }); setRango({ desde, hasta }) }
  const ultimos30 = () => { const fecha = new Date(`${hoy}T00:00:00`); fecha.setDate(fecha.getDate() - 29); usarRango(fecha.toISOString().slice(0, 10), hoy) }
  const aplicar = (event) => { event.preventDefault(); if (!entradas.desde || !entradas.hasta || entradas.desde > entradas.hasta) return setError('Selecciona un rango de fechas válido.'); setRango(entradas) }

  const columnas = {
    dias: [['fecha', 'Fecha', (i) => fechaCorta(i.fecha)], ['realizados', 'Pedidos'], ['aprobados', 'Aprobados'], ['pendientes', 'Pendientes'], ['modificados', 'Modificados'], ['cuadresRealizados', 'Cuadres'], ['cuadresModificados', 'Cuadres modificados'], ['unidadesVendidas', 'Vendido'], ['unidadesSobrantes', 'Sobrante'], ['montoVendido', 'Valor vendido', (i) => money.format(i.montoVendido)]],
    rutas: [['ruta', 'Ruta'], ['realizados', 'Pedidos'], ['aprobados', 'Aprobados'], ['pendientes', 'Pendientes'], ['modificados', 'Modificados'], ['montoAprobado', 'Monto aprobado', (i) => money.format(i.montoAprobado)], ['cuadresRealizados', 'Cuadres'], ['cuadresPendientes', 'Cuadres pendientes'], ['cuadresModificados', 'Cuadres modificados'], ['unidadesVendidas', 'Vendido'], ['unidadesSobrantes', 'Sobrante'], ['montoVendido', 'Valor vendido', (i) => money.format(i.montoVendido)]],
    productos: [['producto', 'Producto'], ['tipoProducto', 'Tipo'], ['cantidadRutas', 'Rutas'], ['cantidadCuadres', 'Cuadres'], ['vendidos', 'Vendido'], ['sobrantes', 'Sobrante'], ['totalVendido', 'Valor vendido', (i) => money.format(i.totalVendido)]],
    vendedores: [['vendedor', 'Vendedor'], ['pedidos', 'Pedidos'], ['aprobados', 'Aprobados'], ['pendientes', 'Pendientes'], ['modificados', 'Modificados'], ['unidadesSolicitadas', 'Unidades pedidas'], ['montoSolicitado', 'Monto solicitado', (i) => money.format(i.montoSolicitado)]],
    consumo: [['mes', 'Mes'], ['producto', 'Producto'], ['tipoProducto', 'Tipo'], ['vendidos', 'Consumido'], ['diasConVenta', 'Días con consumo'], ['frecuencia', 'Regularidad', (i) => `${i.frecuencia.toFixed(1)}%`], ['promedioDiario', 'Promedio/día', (i) => i.promedioDiario.toFixed(1)], ['promedioDiaActivo', 'Promedio/día activo', (i) => i.promedioDiaActivo.toFixed(1)], ['cuadres', 'Cuadres'], ['totalVendido', 'Valor reportado', (i) => money.format(i.totalVendido)]],
    cuadres: [['fecha', 'Fecha', (i) => fechaCorta(i.fecha)], ['ruta', 'Ruta'], ['idCuadre', 'Cuadre', (i) => `#${i.idCuadre}`], ['producto', 'Producto'], ['tipoProducto', 'Tipo'], ['sobrantes', 'Sobrante'], ['vendidos', 'Vendido'], ['precio', 'Precio', (i) => money.format(i.precio)], ['totalVendido', 'Total vendido', (i) => money.format(i.totalVendido)]],
  }
  const filas = vista === 'dias' ? ordenar(dias) : vista === 'rutas' ? ordenar(rutas) : vista === 'productos' ? ordenar(productos) : vista === 'vendedores' ? ordenar(vendedoresOrdenados) : vista === 'consumo' ? ordenar(consumoMensual) : ordenar(detalle.map((item) => ({ ...item, sobrantes: Number(item.sobrantes || 0), vendidos: Number(item.vendidos || 0), precio: Number(item.precio || 0), totalVendido: Number(item.totalVendido || 0) })))

  return <section className="warehouse-statistics detailed-statistics">
    <header className="statistics-heading"><div><p>ANÁLISIS OPERATIVO</p><h2>Estadísticas de almacén</h2><span>Pedidos, cuadres y venta reportada por fecha, ruta y producto.</span></div><form onSubmit={aplicar}><label>Desde<input type="date" value={entradas.desde} max={entradas.hasta} onChange={(e) => setEntradas({ ...entradas, desde: e.target.value })} /></label><label>Hasta<input type="date" value={entradas.hasta} min={entradas.desde} max={hoy} onChange={(e) => setEntradas({ ...entradas, hasta: e.target.value })} /></label><button>Actualizar</button></form></header>
    <div className="statistics-shortcuts"><button onClick={() => usarRango(hoy, hoy)}>Hoy</button><button onClick={() => usarRango(inicioMes, hoy)}>Este mes</button><button onClick={ultimos30}>Últimos 30 días</button><span>{fechaCorta(rango.desde)} — {fechaCorta(rango.hasta)}</span></div>
    {cargando ? <div className="statistics-message">Consultando estadísticas…</div> : error ? <div className="statistics-message error">{error}</div> : <>
      <div className="statistics-kpis expanded"><article className="created"><span>Pedidos realizados</span><strong>{integer.format(totales.realizados)}</strong><small>{integer.format(totales.unidadesSolicitadas)} unidades solicitadas</small></article><article className="approved"><span>Pedidos aprobados</span><strong>{integer.format(totales.aprobados)}</strong><small>{integer.format(totales.unidadesAprobadas)} unidades · {money.format(totales.montoAprobado)}</small></article><article className="modified"><span>Pedidos modificados</span><strong>{integer.format(totales.modificados)}</strong><small>Ajustes realizados por almacén</small></article><article className="cashups"><span>Cuadres realizados</span><strong>{integer.format(totales.cuadresRealizados)}</strong><small>{integer.format(totales.cuadresPendientes)} preliminar(es) pendiente(s)</small></article><article className="sold"><span>Vendido reportado</span><strong>{integer.format(totales.unidadesVendidas)}</strong><small>Unidades declaradas en cuadres</small></article><article className="revenue"><span>Valor vendido reportado</span><strong>{money.format(totales.montoVendido)}</strong><small>{integer.format(totales.unidadesSobrantes)} unidades sobrantes</small></article></div>
      <section className="statistics-leaders">
        <article><span>Vendedor con más pedidos</span><strong>{vendedorTop?.vendedor || 'Sin datos'}</strong><small>{vendedorTop ? `${integer.format(vendedorTop.pedidos)} pedido(s) · ${integer.format(vendedorTop.unidadesSolicitadas)} unidades` : 'Sin pedidos en el periodo'}</small></article>
        <article><span>Ruta con más pedidos</span><strong>{rutaTop?.ruta || 'Sin datos'}</strong><small>{rutaTop ? `${integer.format(rutaTop.realizados)} pedido(s) · ${integer.format(rutaTop.unidadesSolicitadas)} unidades` : 'Sin movimiento en el periodo'}</small></article>
        <article><span>Tarjeta más vendida</span><strong>{tarjetaTop?.producto || 'Sin datos'}</strong><small>{tarjetaTop ? `${integer.format(tarjetaTop.vendidos)} unidades · ${tarjetaTop.frecuencia.toFixed(1)}% de regularidad` : 'Sin tarjetas vendidas reportadas'}</small></article>
        <article><span>Producto más consumido</span><strong>{productoTop?.producto || 'Sin datos'}</strong><small>{productoTop ? `${integer.format(productoTop.vendidos)} unidades · ${productoTop.promedioDiario.toFixed(1)} por día` : 'Sin consumo reportado'}</small></article>
      </section>
      <div className="statistics-viewbar"><div>{[['resumen', 'Resumen'], ['cuadresAnalisis', 'Análisis de cuadres'], ['vendedores', 'Por vendedor'], ['rutas', 'Por rutas'], ['consumo', 'Consumo de productos'], ['dias', 'Tabla diaria'], ['productos', 'Por producto'], ['cuadres', 'Detalle de cuadres']].map(([id, texto]) => <button className={vista === id ? 'active' : ''} key={id} onClick={() => setVista(id)}>{texto}</button>)}</div>{!['resumen', 'cuadresAnalisis'].includes(vista) && <label><span>⌕</span><input type="search" value={busqueda} onChange={(e) => setBusqueda(e.target.value)} placeholder="Buscar vendedor, ruta, producto o mes…" /></label>}</div>
      {vista === 'resumen' && <StatisticsMonthComparison actual={totales} anterior={totalesAnteriores} rango={rango} rangoAnterior={rangoAnterior} />}
      {vista === 'resumen' ? <><section className="statistics-card daily-statistics"><div className="statistics-card-head"><div><p>COMPORTAMIENTO DIARIO</p><h3>Actividad por día</h3></div><div className="statistics-legend"><span className="created">Pedidos</span><span className="approved">Aprobados</span><span className="cashups">Cuadres</span></div></div><div className="statistics-chart-scroll"><div className="daily-chart" style={{ minWidth: `${Math.max(680, dias.length * 58)}px` }}>{[...dias].sort((a, b) => a.fecha.localeCompare(b.fecha)).map((item) => <div className="daily-column" key={item.fecha} title={`${item.fecha}: ${item.realizados} pedidos, ${item.aprobados} aprobados, ${item.cuadresRealizados} cuadres, ${item.unidadesVendidas} vendidos`}><div className="daily-values"><span>{item.realizados || ''}</span><span>{item.aprobados || ''}</span><span>{item.cuadresRealizados || ''}</span></div><div className="daily-bars"><i className="created" style={{ height: `${item.realizados ? Math.max(5, item.realizados * 100 / maxDia) : 0}%` }} /><i className="approved" style={{ height: `${item.aprobados ? Math.max(5, item.aprobados * 100 / maxDia) : 0}%` }} /><i className="cashups" style={{ height: `${item.cuadresRealizados ? Math.max(5, item.cuadresRealizados * 100 / maxDia) : 0}%` }} /></div><small>{fechaCorta(item.fecha)}</small></div>)}</div></div></section><section className="statistics-card"><div className="statistics-card-head"><div><p>RESULTADO DECLARADO</p><h3>Venta reportada por ruta</h3></div><span>{rutas.length} ruta(s) con movimiento</span></div><div className="statistics-ranking">{[...rutas].sort((a, b) => b.montoVendido - a.montoVendido).slice(0, 10).map((item) => <article key={item.idRuta}><div><strong>{item.ruta}</strong><small>{integer.format(item.unidadesVendidas)} vendidas · {integer.format(item.unidadesSobrantes)} sobrantes · {item.cuadresRealizados} cuadre(s)</small></div><b>{money.format(item.montoVendido)}</b></article>)}</div></section></> : <>
        {vista === 'vendedores' && <StatisticsRankingChart title="Vendedores que más pedidos realizan" rows={vendedoresOrdenados} label="vendedor" value="pedidos" suffix="pedido(s)" />}
        {vista === 'rutas' && <StatisticsRankingChart title="Rutas con más pedidos" rows={rutasOrdenadas} label="ruta" value="realizados" suffix="pedido(s)" />}
        {vista === 'cuadresAnalisis' && <CashupAnalyticsPanel totales={totales} anteriores={totalesAnteriores} dias={dias} rutas={rutas} rango={rango} rangoAnterior={rangoAnterior} fechaCorta={fechaCorta} demoras={demorasCaja} demorasAnteriores={demorasCajaAnteriores} />}
        {vista === 'consumo' && <ProductConsumptionCharts consumoDiario={consumoDiario} productos={productosConsumo} detalle={detalle} rutas={rutas} fechaCorta={fechaCorta} rango={rango} />}
        {vista !== 'cuadresAnalisis' && <StatisticsDataTable columns={columnas[vista]} rows={filas} encabezado={encabezado} />}
      </>}
    </>}
  </section>
}

function StatisticsMonthComparison({ actual, anterior, rango, rangoAnterior }) {
  const cambio = (valor, previo) => previo ? (Number(valor || 0) - Number(previo || 0)) * 100 / Math.abs(previo) : null
  const metricas = [
    ['Pedidos', 'realizados', integer], ['Aprobados', 'aprobados', integer], ['Cuadres completos', 'cuadresRealizados', integer],
    ['Cuadres modificados', 'cuadresModificados', integer], ['Unidades vendidas', 'unidadesVendidas', integer], ['Valor vendido', 'montoVendido', money],
  ]
  return <section className="statistics-card month-comparison"><div className="statistics-card-head"><div><p>COMPARACIÓN DEL PERIODO</p><h3>Periodo actual frente al mes anterior</h3></div><span>{rango.desde} — {rango.hasta}<br />vs. {rangoAnterior.desde} — {rangoAnterior.hasta}</span></div><div className="month-comparison-grid">{metricas.map(([nombre, campo, formato]) => { const variacion = cambio(actual[campo], anterior[campo]); const positiva = variacion !== null && variacion >= 0; return <article key={campo}><span>{nombre}</span><strong>{formato.format(actual[campo] || 0)}</strong><small>Anterior: {formato.format(anterior[campo] || 0)}</small><b className={variacion === null ? 'neutral' : positiva ? 'up' : 'down'}>{variacion === null ? 'Sin base comparable' : `${positiva ? '▲' : '▼'} ${Math.abs(variacion).toFixed(1)}%`}</b></article> })}</div></section>
}

function CashupAnalyticsPanel({ totales, anteriores, dias, rutas, rango, rangoAnterior, fechaCorta, demoras, demorasAnteriores }) {
  const saldo = Number(totales.unidadesVendidas || 0) + Number(totales.unidadesSobrantes || 0)
  const saldoAnterior = Number(anteriores.unidadesVendidas || 0) + Number(anteriores.unidadesSobrantes || 0)
  const cumplimiento = saldo ? Number(totales.unidadesVendidas || 0) * 100 / saldo : 0
  const cumplimientoAnterior = saldoAnterior ? Number(anteriores.unidadesVendidas || 0) * 100 / saldoAnterior : 0
  const promedio = totales.cuadresRealizados ? totales.unidadesVendidas / totales.cuadresRealizados : 0
  const promedioValor = totales.cuadresRealizados ? totales.montoVendido / totales.cuadresRealizados : 0
  const maxDia = Math.max(1, ...dias.flatMap((item) => [item.cuadresRealizados, item.cuadresPendientes, item.cuadresModificados]))
  const rutasOrdenadas = [...rutas].filter((item) => item.cuadresEnviados || item.cuadresRealizados || item.unidadesVendidas || item.unidadesSobrantes).sort((a, b) => b.unidadesVendidas - a.unidadesVendidas)
  const totalInventario = Math.max(1, saldo)
  return <section className="cashup-analytics">
    <StatisticsMonthComparison actual={totales} anterior={anteriores} rango={rango} rangoAnterior={rangoAnterior} />
    <div className="cashup-kpi-grid"><article><span>Cuadres enviados</span><strong>{integer.format(totales.cuadresEnviados)}</strong><small>Versiones recibidas</small></article><article className="complete"><span>Cuadres completos</span><strong>{integer.format(totales.cuadresRealizados)}</strong><small>Aplicados al inventario</small></article><article className="pending"><span>Pendientes</span><strong>{integer.format(totales.cuadresPendientes)}</strong><small>Esperan revisión</small></article><article className="modified"><span>Modificados</span><strong>{integer.format(totales.cuadresModificados)}</strong><small>Ajustados por almacén</small></article><article><span>Saldo evaluado</span><strong>{integer.format(saldo)}</strong><small>Vendido + sobrante</small></article><article className="sold"><span>Vendido</span><strong>{integer.format(totales.unidadesVendidas)}</strong><small>{money.format(totales.montoVendido)}</small></article><article><span>Sobrante</span><strong>{integer.format(totales.unidadesSobrantes)}</strong><small>Inventario declarado</small></article><article><span>Efectividad</span><strong>{cumplimiento.toFixed(1)}%</strong><small>Mes anterior: {cumplimientoAnterior.toFixed(1)}%</small></article><article><span>Promedio por cuadre</span><strong>{promedio.toFixed(1)}</strong><small>{money.format(promedioValor)} por cuadre</small></article></div>
    <div className="cashup-analysis-grid"><section className="statistics-card cashup-balance-card"><div className="statistics-card-head"><div><p>DESTINO DEL SALDO</p><h3>Vendido frente a sobrante</h3></div><span>{integer.format(saldo)} unidades controladas</span></div><div className="cashup-balance-visual"><div className="cashup-donut" style={{ background: `conic-gradient(#27866b 0 ${cumplimiento}%, #d49a31 ${cumplimiento}% 100%)` }}><div><strong>{cumplimiento.toFixed(1)}%</strong><span>vendido</span></div></div><div><article><i className="sold" /><span>Vendido</span><strong>{integer.format(totales.unidadesVendidas)}</strong></article><article><i className="left" /><span>Sobrante</span><strong>{integer.format(totales.unidadesSobrantes)}</strong></article><p>Cada unidad del saldo evaluado debe terminar como vendida o sobrante.</p></div></div></section><section className="statistics-card cashup-status-card"><div className="statistics-card-head"><div><p>CALIDAD DEL PROCESO</p><h3>Estado de los cuadres</h3></div></div>{[['Completos', totales.cuadresRealizados, '#27866b'], ['Pendientes', totales.cuadresPendientes, '#d49a31'], ['Modificados', totales.cuadresModificados, '#ba654e']].map(([nombre, valor, color]) => { const base = Math.max(1, totales.cuadresEnviados, totales.cuadresRealizados); return <article key={nombre}><header><strong>{nombre}</strong><b>{integer.format(valor)}</b></header><i><span style={{ width: `${Math.min(100, valor * 100 / base)}%`, background: color }} /></i></article> })}</section></div>
    <section className="statistics-card cashup-daily-card"><div className="statistics-card-head"><div><p>EVOLUCIÓN DIARIA</p><h3>Cuadres completos, pendientes y modificados</h3></div><div className="statistics-legend"><span className="cashups">Completos</span><span className="modified">Modificados</span><span className="pending">Pendientes</span></div></div><div className="statistics-chart-scroll"><div className="daily-chart cashup-daily-chart" style={{ minWidth: `${Math.max(720, dias.length * 72)}px` }}>{[...dias].sort((a, b) => a.fecha.localeCompare(b.fecha)).map((item) => <div className="daily-column" key={item.fecha}><div className="daily-values"><span>{item.cuadresRealizados || ''}</span><span>{item.cuadresModificados || ''}</span><span>{item.cuadresPendientes || ''}</span></div><div className="daily-bars"><i className="cashups" style={{ height: `${item.cuadresRealizados ? Math.max(5, item.cuadresRealizados * 100 / maxDia) : 0}%` }} /><i className="modified" style={{ height: `${item.cuadresModificados ? Math.max(5, item.cuadresModificados * 100 / maxDia) : 0}%` }} /><i className="pending" style={{ height: `${item.cuadresPendientes ? Math.max(5, item.cuadresPendientes * 100 / maxDia) : 0}%` }} /></div><small>{fechaCorta(item.fecha)}</small></div>)}</div></div></section>
    <CashupDelayPanel demoras={demoras} anteriores={demorasAnteriores} fechaCorta={fechaCorta} />
    <section className="statistics-card cashup-route-table"><div className="statistics-card-head"><div><p>CONTROL POR RUTA</p><h3>Rendimiento y estado de cada ruta</h3></div><span>{rutasOrdenadas.length} ruta(s) con actividad</span></div><div className="statistics-table-scroll"><table><thead><tr><th>Ruta</th><th>Completos</th><th>Pendientes</th><th>Modificados</th><th>Saldo</th><th>Vendido</th><th>Sobrante</th><th>Efectividad</th><th>Valor vendido</th></tr></thead><tbody>{rutasOrdenadas.map((item) => { const inventario = Number(item.unidadesVendidas || 0) + Number(item.unidadesSobrantes || 0); const tasa = inventario ? Number(item.unidadesVendidas || 0) * 100 / inventario : 0; return <tr key={item.idRuta}><td><strong>{item.ruta}</strong></td><td>{integer.format(item.cuadresRealizados)}</td><td>{integer.format(item.cuadresPendientes)}</td><td>{integer.format(item.cuadresModificados)}</td><td>{integer.format(inventario)}</td><td>{integer.format(item.unidadesVendidas)}</td><td>{integer.format(item.unidadesSobrantes)}</td><td><span className="cashup-rate"><i><b style={{ width: `${tasa}%` }} /></i>{tasa.toFixed(1)}%</span></td><td>{money.format(item.montoVendido)}</td></tr> })}</tbody></table></div></section>
  </section>
}

function CashupDelayPanel({ demoras, anteriores, fechaCorta }) {
  const [ruta, setRuta] = useState('')
  const visibles = ruta ? demoras.filter((item) => Number(item.idRuta) === Number(ruta)) : demoras
  const promedio = (filas) => filas.length ? filas.reduce((total, item) => total + Number(item.minutosDemora || 0), 0) / filas.length : 0
  const promedioActual = promedio(visibles)
  const promedioAnterior = promedio(ruta ? anteriores.filter((item) => Number(item.idRuta) === Number(ruta)) : anteriores)
  const variacion = promedioAnterior ? (promedioActual - promedioAnterior) * 100 / promedioAnterior : null
  const maximo = visibles.reduce((mayor, item) => Number(item.minutosDemora || 0) > Number(mayor?.minutosDemora || -1) ? item : mayor, null)
  const porDia = new Map()
  visibles.forEach((item) => { const actual = porDia.get(item.fecha); if (!actual || Number(item.minutosDemora) > Number(actual.minutosDemora)) porDia.set(item.fecha, item) })
  const diasLentos = [...porDia.values()].sort((a, b) => a.fecha.localeCompare(b.fecha))
  const maxDia = Math.max(1, ...diasLentos.map((item) => Number(item.minutosDemora || 0)))
  const vendedores = new Map()
  visibles.forEach((item) => { const actual = vendedores.get(item.idVendedor) || { idVendedor: item.idVendedor, vendedor: item.vendedor, ruta: item.ruta, total: 0, cantidad: 0, maximo: 0 }; actual.total += Number(item.minutosDemora || 0); actual.cantidad += 1; actual.maximo = Math.max(actual.maximo, Number(item.minutosDemora || 0)); vendedores.set(item.idVendedor, actual) })
  const ranking = [...vendedores.values()].map((item) => ({ ...item, promedio: item.total / item.cantidad })).sort((a, b) => b.promedio - a.promedio)
  const rutas = [...new Map(demoras.map((item) => [item.idRuta, { idRuta: item.idRuta, ruta: item.ruta }])).values()].sort((a, b) => String(a.ruta).localeCompare(String(b.ruta), 'es', { numeric: true }))
  const formatoTiempo = (minutos) => minutos >= 60 ? `${Math.floor(minutos / 60)} h ${Math.round(minutos % 60)} min` : `${Math.round(minutos)} min`
  return <section className="cashup-delay-dashboard">
    <section className="statistics-card cashup-delay-heading"><div><p>TIEMPO HASTA CAJA</p><h3>Demora después de realizar el cuadre</h3><span>Desde la fecha del cuadre hasta su primer movimiento válido en caja.</span></div><label>Ruta<select value={ruta} onChange={(event) => setRuta(event.target.value)}><option value="">Todas las rutas</option>{rutas.map((item) => <option key={item.idRuta} value={item.idRuta}>{item.ruta}</option>)}</select></label></section>
    <div className="cashup-delay-kpis"><article><span>Promedio del periodo</span><strong>{formatoTiempo(promedioActual)}</strong><small>Anterior: {formatoTiempo(promedioAnterior)}</small><b className={variacion === null ? 'neutral' : variacion <= 0 ? 'good' : 'bad'}>{variacion === null ? 'Sin base anterior' : `${variacion <= 0 ? '▼' : '▲'} ${Math.abs(variacion).toFixed(1)}% de demora`}</b></article><article><span>Mayor demora</span><strong>{maximo ? formatoTiempo(maximo.minutosDemora) : '0 min'}</strong><small>{maximo ? `${maximo.vendedor} · ${maximo.ruta}` : 'Sin registros'}</small></article><article><span>Más de 30 minutos</span><strong>{integer.format(visibles.filter((item) => Number(item.minutosDemora) > 30).length)}</strong><small>de {integer.format(visibles.length)} cuadre(s) con paso por caja</small></article><article><span>En 15 minutos o menos</span><strong>{visibles.length ? `${(visibles.filter((item) => Number(item.minutosDemora) <= 15).length * 100 / visibles.length).toFixed(1)}%` : '0%'}</strong><small>Nivel de atención rápida</small></article></div>
    <div className="cashup-delay-layout"><section className="statistics-card cashup-delay-days"><div className="statistics-card-head"><div><p>MÁXIMO DE CADA DÍA</p><h3>Quién tardó más en pasar por caja</h3></div><span>{diasLentos.length} día(s)</span></div>{diasLentos.length === 0 ? <div className="statistics-message">No existen pasos por caja en este periodo.</div> : <div className="delay-day-bars">{diasLentos.map((item) => <article key={item.fecha}><time>{fechaCorta(item.fecha)}</time><div><i><span style={{ width: `${Math.max(3, Number(item.minutosDemora) * 100 / maxDia)}%` }} /></i><strong>{item.vendedor}</strong><small>{item.ruta} · Cuadre #{item.idCuadre}</small></div><b>{formatoTiempo(item.minutosDemora)}</b></article>)}</div>}</section><section className="statistics-card cashup-delay-ranking"><div className="statistics-card-head"><div><p>DEMORA HABITUAL</p><h3>Promedio por vendedor</h3></div><span>Mayor promedio primero</span></div><div>{ranking.slice(0, 12).map((item, index) => <article key={item.idVendedor}><b>{index + 1}</b><div><strong>{item.vendedor}</strong><small>{item.ruta} · {item.cantidad} cuadre(s)</small></div><span>{formatoTiempo(item.promedio)}<small>máx. {formatoTiempo(item.maximo)}</small></span></article>)}</div></section></div>
    <section className="statistics-card cashup-delay-table"><div className="statistics-card-head"><div><p>TRAZABILIDAD</p><h3>Detalle de pasos por caja</h3></div><span>{visibles.length} registro(s)</span></div><div className="statistics-table-scroll"><table><thead><tr><th>Fecha</th><th>Vendedor</th><th>Ruta</th><th>Cuadre</th><th>Caja</th><th>Hora cuadre</th><th>Hora caja</th><th>Demora</th></tr></thead><tbody>{[...visibles].sort((a, b) => Number(b.minutosDemora) - Number(a.minutosDemora)).map((item) => <tr key={item.idCuadre}><td>{fechaCorta(item.fecha)}</td><td><strong>{item.vendedor}</strong></td><td>{item.ruta}</td><td>#{item.idCuadre}</td><td>#{item.idCaja}</td><td>{new Date(item.fechaCuadre).toLocaleTimeString('es-BO', { hour: '2-digit', minute: '2-digit' })}</td><td>{new Date(item.fechaCaja).toLocaleTimeString('es-BO', { hour: '2-digit', minute: '2-digit' })}</td><td><b className={Number(item.minutosDemora) > 30 ? 'delay-alert' : ''}>{formatoTiempo(item.minutosDemora)}</b></td></tr>)}</tbody></table></div></section>
  </section>
}

function StatisticsDataTable({ columns, rows, encabezado }) {
  return <section className="statistics-card statistics-table-card"><div className="statistics-card-head"><div><p>DETALLE INTERACTIVO</p><h3>{integer.format(rows.length)} registro(s)</h3></div><span>Selecciona una columna para ordenar</span></div>{rows.length === 0 ? <div className="statistics-message">No existen registros en el periodo seleccionado.</div> : <div className="statistics-table-scroll"><table><thead><tr>{columns.map(([campo, texto]) => <th key={campo}>{encabezado(campo, texto)}</th>)}</tr></thead><tbody>{rows.map((item, indice) => <tr key={`${item.fecha || 'total'}-${item.idRuta || item.idProducto || indice}-${item.idCuadre || indice}`}>{columns.map(([campo, , formato]) => <td key={campo}>{formato ? formato(item) : typeof item[campo] === 'number' ? integer.format(item[campo]) : item[campo]}</td>)}</tr>)}</tbody></table></div>}</section>
}

function StatisticsRankingChart({ title, rows, label, value, suffix }) {
  const destacados = [...rows].sort((a, b) => Number(b[value] || 0) - Number(a[value] || 0)).slice(0, 10)
  const maximo = Math.max(1, ...destacados.map((item) => Number(item[value] || 0)))
  return <section className="statistics-card statistics-ranking-chart">
    <div className="statistics-card-head"><div><p>RANKING DEL PERIODO</p><h3>{title}</h3></div><span>Top {destacados.length}</span></div>
    {destacados.length === 0 ? <div className="statistics-message">No existen datos para construir el ranking.</div> : <div className="statistics-horizontal-bars">{destacados.map((item, index) => <article key={`${item[label]}-${index}`}><b>{index + 1}</b><div><header><strong>{item[label]}</strong><span>{integer.format(Number(item[value] || 0))} {suffix}</span></header><i><span style={{ width: `${Math.max(2, Number(item[value] || 0) * 100 / maximo)}%` }} /></i></div></article>)}</div>}
  </section>
}

function ProductConsumptionCharts({ consumoDiario, productos, detalle, rutas, fechaCorta, rango }) {
  const [modo, setModo] = useState('fecha')
  const [rutaSeleccionada, setRutaSeleccionada] = useState('')
  const colores = ['#234a66', '#2c8870', '#d38a1b', '#7b6aa6', '#c65b54', '#3985a0', '#8a7045', '#657a87']
  const detalleRuta = rutaSeleccionada ? detalle.filter((item) => Number(item.idRuta) === Number(rutaSeleccionada)) : detalle
  const productosRutaMap = new Map()
  detalleRuta.forEach((item) => {
    const actual = productosRutaMap.get(item.idProducto) || { idProducto: item.idProducto, producto: item.producto, tipoProducto: item.tipoProducto, vendidos: 0, sobrantes: 0, totalVendido: 0 }
    actual.vendidos += Number(item.vendidos || 0); actual.sobrantes += Number(item.sobrantes || 0); actual.totalVendido += Number(item.totalVendido || 0)
    productosRutaMap.set(item.idProducto, actual)
  })
  const productosVisibles = rutaSeleccionada ? [...productosRutaMap.values()].sort((a, b) => b.vendidos - a.vendidos) : productos
  const fisicos = productosVisibles.filter((item) => {
    const tipo = String(item.tipoProducto || '').toLowerCase()
    return tipo.includes('tarjeta') || tipo.includes('chip')
  })
  const principales = fisicos.slice(0, 8)
  const totalFisico = principales.reduce((total, item) => total + Number(item.vendidos || 0), 0)
  let acumulado = 0
  const secciones = principales.map((item, index) => {
    const inicio = totalFisico ? acumulado * 100 / totalFisico : 0
    acumulado += Number(item.vendidos || 0)
    const fin = totalFisico ? acumulado * 100 / totalFisico : 0
    return { ...item, color: colores[index % colores.length], inicio, fin, porcentaje: totalFisico ? Number(item.vendidos || 0) * 100 / totalFisico : 0 }
  })
  const fondoTorta = secciones.length ? `conic-gradient(${secciones.map((item) => `${item.color} ${item.inicio}% ${item.fin}%`).join(', ')})` : '#e7ecef'
  const ids = new Set(principales.map((item) => item.idProducto))
  const diasMap = new Map()
  const consumoVisible = rutaSeleccionada ? detalleRuta.map((item) => ({ ...item, unidadesVendidas: item.vendidos })) : consumoDiario
  consumoVisible.filter((item) => ids.has(item.idProducto)).forEach((item) => {
    const dia = diasMap.get(item.fecha) || { fecha: item.fecha, total: 0, productos: new Map() }
    const cantidad = Math.max(0, Number(item.unidadesVendidas || 0))
    dia.productos.set(item.idProducto, cantidad); dia.total += cantidad; diasMap.set(item.fecha, dia)
  })
  for (let fecha = new Date(`${rango.desde}T12:00:00`), fin = new Date(`${rango.hasta}T12:00:00`); fecha <= fin; fecha.setDate(fecha.getDate() + 1)) {
    const clave = fecha.toISOString().slice(0, 10)
    if (!diasMap.has(clave)) diasMap.set(clave, { fecha: clave, total: 0, productos: new Map() })
  }
  const diasProducto = [...diasMap.values()].sort((a, b) => a.fecha.localeCompare(b.fecha))

  return <section className="product-consumption-dashboard">
    <section className="statistics-card product-chart-controls"><div><p>FORMA DE ANÁLISIS</p><strong>Explora el consumo por fecha o por ruta</strong></div><div className="product-view-buttons"><button className={modo === 'fecha' ? 'active' : ''} type="button" onClick={() => setModo('fecha')}>Por fecha</button><button className={modo === 'ruta' ? 'active' : ''} type="button" onClick={() => setModo('ruta')}>Por ruta</button></div><label>Ruta<select value={rutaSeleccionada} onChange={(event) => setRutaSeleccionada(event.target.value)}><option value="">Todas las rutas</option>{[...rutas].sort((a, b) => String(a.ruta).localeCompare(String(b.ruta), 'es', { numeric: true })).map((ruta) => <option key={ruta.idRuta} value={ruta.idRuta}>{ruta.ruta}</option>)}</select></label></section>
    <section className="statistics-card product-share-card">
      <div className="statistics-card-head"><div><p>PARTICIPACIÓN DEL PERIODO</p><h3>Productos físicos más vendidos</h3></div><span>{integer.format(totalFisico)} unidades reportadas</span></div>
      <div className="product-pie-layout">
        <div className="product-pie" style={{ background: fondoTorta }}><div><strong>{integer.format(totalFisico)}</strong><span>unidades</span></div></div>
        <div className="product-pie-legend">{secciones.map((item) => <article key={item.idProducto}><i style={{ background: item.color }} /><div><strong>{item.producto}</strong><small>{integer.format(item.vendidos)} unidades</small></div><b>{item.porcentaje.toFixed(1)}%</b></article>)}</div>
      </div>
    </section>
    {modo === 'fecha' ? <section className="statistics-card product-daily-card">
      <div className="statistics-card-head"><div><p>CAMBIO DE CONSUMO DURANTE EL MES</p><h3>Qué productos se venden más cada día</h3></div><span>Una línea por producto</span></div>
      <div className="product-color-legend">{secciones.map((item) => <span key={item.idProducto}><i style={{ background: item.color }} />{item.producto}</span>)}</div>
      {diasProducto.length === 0 ? <div className="statistics-message">No hay ventas de tarjetas o chips en este periodo.</div> : <ProductDailyLineChart dias={diasProducto} productos={secciones} fechaCorta={fechaCorta} />}
      <p className="product-chart-note">Cada punto muestra las unidades vendidas de ese producto en la fecha indicada. Las cantidades están escritas directamente sobre los puntos.</p>
    </section> : <ProductRouteConsumptionChart detalle={detalle} productos={secciones} rutaSeleccionada={rutaSeleccionada} />}
    <StatisticsRankingChart title="Productos con mayor consumo reportado" rows={fisicos} label="producto" value="vendidos" suffix="unidad(es)" />
  </section>
}

function ProductRouteConsumptionChart({ detalle, productos, rutaSeleccionada }) {
  const ids = new Set(productos.map((item) => item.idProducto))
  const colores = new Map(productos.map((item) => [item.idProducto, item.color]))
  const mapa = new Map()
  detalle.filter((item) => ids.has(item.idProducto) && (!rutaSeleccionada || Number(item.idRuta) === Number(rutaSeleccionada))).forEach((item) => {
    const ruta = mapa.get(item.idRuta) || { idRuta: item.idRuta, ruta: item.ruta, total: 0, productos: new Map() }
    const cantidad = Number(item.vendidos || 0)
    ruta.productos.set(item.idProducto, (ruta.productos.get(item.idProducto) || 0) + cantidad); ruta.total += cantidad; mapa.set(item.idRuta, ruta)
  })
  const filas = [...mapa.values()].sort((a, b) => b.total - a.total)
  const maximo = Math.max(1, ...filas.map((item) => item.total))
  return <section className="statistics-card product-route-card"><div className="statistics-card-head"><div><p>CONSUMO POR RUTA</p><h3>Qué productos consume cada ruta</h3></div><span>Barras apiladas por producto</span></div>{filas.length === 0 ? <div className="statistics-message">No hay ventas físicas para las rutas seleccionadas.</div> : <div className="product-route-bars">{filas.map((fila) => <article key={fila.idRuta}><header><strong>{fila.ruta}</strong><b>{integer.format(fila.total)} unidades</b></header><div className="product-route-track" style={{ width: `${Math.max(8, fila.total * 100 / maximo)}%` }}>{productos.map((producto) => { const cantidad = fila.productos.get(producto.idProducto) || 0; return cantidad ? <i key={producto.idProducto} style={{ width: `${cantidad * 100 / fila.total}%`, background: colores.get(producto.idProducto) }} title={`${producto.producto}: ${integer.format(cantidad)}`}><span>{cantidad * 100 / fila.total > 10 ? integer.format(cantidad) : ''}</span></i> : null })}</div></article>)}</div>}<div className="product-color-legend">{productos.map((item) => <span key={item.idProducto}><i style={{ background: item.color }} />{item.producto}</span>)}</div></section>
}

function ProductDailyLineChart({ dias, productos, fechaCorta }) {
  const ancho = Math.max(920, dias.length * 90)
  const alto = 440
  const margen = { izquierda: 72, derecha: 32, arriba: 48, abajo: 68 }
  const anchoGrafica = ancho - margen.izquierda - margen.derecha
  const altoGrafica = alto - margen.arriba - margen.abajo
  const maximoReal = Math.max(1, ...dias.flatMap((dia) => productos.map((producto) => Number(dia.productos.get(producto.idProducto) || 0))))
  const magnitud = 10 ** Math.max(0, Math.floor(Math.log10(maximoReal)) - 1)
  const maximo = Math.ceil(maximoReal / magnitud) * magnitud
  const x = (indice) => margen.izquierda + (dias.length === 1 ? anchoGrafica / 2 : indice * anchoGrafica / (dias.length - 1))
  const y = (valor) => margen.arriba + altoGrafica - Number(valor || 0) * altoGrafica / maximo
  const marcas = Array.from({ length: 6 }, (_, indice) => maximo * indice / 5)

  return <div className="product-line-scroll">
    <svg className="product-line-chart" viewBox={`0 0 ${ancho} ${alto}`} style={{ width: `${ancho}px` }} role="img" aria-label="Ventas diarias por producto">
      {marcas.map((valor) => { const posicionY = y(valor); return <g key={valor}><line x1={margen.izquierda} x2={ancho - margen.derecha} y1={posicionY} y2={posicionY} className="product-line-grid" /><text x={margen.izquierda - 12} y={posicionY + 4} textAnchor="end" className="product-line-axis-value">{integer.format(Math.round(valor))}</text></g> })}
      <line x1={margen.izquierda} x2={margen.izquierda} y1={margen.arriba} y2={alto - margen.abajo} className="product-line-axis" />
      <line x1={margen.izquierda} x2={ancho - margen.derecha} y1={alto - margen.abajo} y2={alto - margen.abajo} className="product-line-axis" />
      {dias.map((dia, indice) => <g key={dia.fecha}><line x1={x(indice)} x2={x(indice)} y1={margen.arriba} y2={alto - margen.abajo} className="product-line-day-grid" /><text transform={`translate(${x(indice) - 4} ${alto - margen.abajo + 21}) rotate(-35)`} textAnchor="end" className="product-line-date">{fechaCorta(dia.fecha)}</text></g>)}
      {productos.map((producto, productoIndice) => {
        const puntos = dias.map((dia, indice) => `${x(indice)},${y(dia.productos.get(producto.idProducto) || 0)}`).join(' ')
        return <g key={producto.idProducto} className="product-line-series">
          <polyline points={puntos} fill="none" stroke={producto.color} strokeWidth="3" strokeLinejoin="round" strokeLinecap="round" />
          {dias.map((dia, indice) => {
            const cantidad = Number(dia.productos.get(producto.idProducto) || 0)
            if (cantidad <= 0) return null
            const puntoX = x(indice); const puntoY = y(cantidad)
            const etiquetaY = Math.max(17, puntoY - 10 - (productoIndice % 3) * 11)
            return <g key={`${dia.fecha}-${producto.idProducto}`}><circle cx={puntoX} cy={puntoY} r="5" fill={producto.color} stroke="#fff" strokeWidth="2"><title>{`${fechaCorta(dia.fecha)} · ${producto.producto}: ${integer.format(cantidad)} unidades`}</title></circle><text x={puntoX} y={etiquetaY} textAnchor="middle" className="product-line-point-value" fill={producto.color}>{integer.format(cantidad)}</text></g>
          })}
        </g>
      })}
      <text x={18} y={margen.arriba + altoGrafica / 2} transform={`rotate(-90 18 ${margen.arriba + altoGrafica / 2})`} textAnchor="middle" className="product-line-axis-title">UNIDADES VENDIDAS</text>
      <text x={margen.izquierda + anchoGrafica / 2} y={alto - 8} textAnchor="middle" className="product-line-axis-title">FECHA</text>
    </svg>
  </div>
}

function parsePreliminaryStrips(xml) {
  if (!xml) return []
  try {
    return [...new DOMParser().parseFromString(xml, 'application/xml').querySelectorAll('tira')].map((node) => {
      const imeis = [...node.querySelectorAll('i')].map((item) => item.getAttribute('v'))
      return {
        idProducto: Number(node.getAttribute('producto')),
        numero: Number(node.getAttribute('numero')),
        modo: node.getAttribute('modo'),
        cantidad: ['tigo_money', 'chip_cantidad'].includes(node.getAttribute('modo')) ? Number(node.getAttribute('cantidad')) : imeis.length,
        efectivizacion: Number(node.getAttribute('efectivizacion') || 0),
        inicio: imeis[0] || '0', final: imeis.at(-1) || '0',
      }
    })
  } catch { return [] }
}

function WarehouseCuadresPanel({ session, onResumenHoy, onPendientesHoy }) {
  const hoy = new Date().toISOString().slice(0, 10)
  const [fecha, setFecha] = useState(hoy)
  const [rutasCuadre, setRutasCuadre] = useState([])
  const [idRuta, setIdRuta] = useState('')
  const [busqueda, setBusqueda] = useState('')
  const [filtro, setFiltro] = useState('todos')
  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState('')
  const [detalle, setDetalle] = useState(null)
  const [cargandoDetalle, setCargandoDetalle] = useState(false)
  const [saldoRuta, setSaldoRuta] = useState(null)
  const [rutaSaldo, setRutaSaldo] = useState(null)
  const [cargandoSaldoRuta, setCargandoSaldoRuta] = useState(false)
  const [rutaParaCuadre, setRutaParaCuadre] = useState(null)
  const [recarga, setRecarga] = useState(0)
  const [vistaCuadres, setVistaCuadres] = useState('preliminares')
  const [preliminares, setPreliminares] = useState([])
  const [detallePreliminar, setDetallePreliminar] = useState(null)
  const [cargandoPreliminar, setCargandoPreliminar] = useState(false)
  const [procesandoPreliminar, setProcesandoPreliminar] = useState(false)
  const [preliminarModificar, setPreliminarModificar] = useState(null)
  const [ventasDia, setVentasDia] = useState([])
  const [cargandoVentas, setCargandoVentas] = useState(true)
  const [errorVentas, setErrorVentas] = useState('')

  useEffect(() => {
    let activo = true
    setCargandoVentas(true)
    setErrorVentas('')
    api(`/api/auth/almacen/estadisticas/cuadres-detalle?fechaDesde=${fecha}&fechaHasta=${fecha}`, { headers: { Authorization: `Bearer ${session.token}` } })
      .then((data) => { if (activo) setVentasDia(data) })
      .catch((err) => { if (activo) { setVentasDia([]); setErrorVentas(err.message) } })
      .finally(() => { if (activo) setCargandoVentas(false) })
    return () => { activo = false }
  }, [fecha, session.token, recarga])

  useEffect(() => {
    let activo = true
    setCargando(true)
    setError('')
    Promise.all([
      api(`/api/auth/almacen/cuadres/rutas?fecha=${fecha}`, { headers: { Authorization: `Bearer ${session.token}` } }),
      api(`/api/auth/almacen/cuadres-preliminares?fecha=${fecha}`, { headers: { Authorization: `Bearer ${session.token}` } }),
    ]).then(([data, preliminaresData]) => {
        if (!activo) return
        setRutasCuadre(data)
        setPreliminares(preliminaresData)
        if (fecha === hoy) onResumenHoy?.(data.filter((item) => item.realizoCuadre).length)
        if (fecha === hoy) onPendientesHoy?.(preliminaresData.filter((item) => item.estadoAprobado === 1).length)
      })
      .catch((err) => { if (activo) setError(err.message) })
      .finally(() => { if (activo) setCargando(false) })
    return () => { activo = false }
  }, [fecha, hoy, onResumenHoy, onPendientesHoy, session.token, recarga])

  const realizadas = rutasCuadre.filter((item) => item.realizoCuadre).length
  const pendientes = rutasCuadre.length - realizadas
  const pendientesRevision = preliminares.filter((item) => item.estadoAprobado === 1).length
  const pendientesPorRuta = preliminares.reduce((conteo, item) => {
    if (item.estadoAprobado === 1) conteo[item.idRuta] = (conteo[item.idRuta] || 0) + 1
    return conteo
  }, {})
  const rutasModificadas = new Set(preliminares.filter((item) => item.modificado).map((item) => item.idRuta))
  const rutasBuscadas = rutasCuadre
    .filter((item) => `${item.ruta} ${item.tecnico}`.toLowerCase().includes(busqueda.trim().toLowerCase()))
    .sort((a, b) => (pendientesPorRuta[b.idRuta] || 0) - (pendientesPorRuta[a.idRuta] || 0))
  const rutasVisibles = rutasCuadre.filter((item) => {
    if (idRuta && item.idRuta !== Number(idRuta)) return false
    if (filtro === 'realizados') return item.realizoCuadre
    if (filtro === 'sin_cuadre') return !item.realizoCuadre
    return true
  })
  const rutaSeleccionada = rutasCuadre.find((item) => item.idRuta === Number(idRuta))
  const preliminaresVisibles = preliminares.filter((item) => !idRuta || item.idRuta === Number(idRuta))
  const tirasPreliminar = parsePreliminaryStrips(detallePreliminar?.tirasXml)
  const ventasVisibles = ventasDia.filter((item) => !idRuta || item.idRuta === Number(idRuta))
  const vendidoConChips = ventasVisibles.reduce((total, item) => total + Number(item.totalVendido || 0), 0)
  const vendidoChips = ventasVisibles
    .filter((item) => item.tipoProducto?.trim().toLowerCase() === 'chip')
    .reduce((total, item) => total + Number(item.totalVendido || 0), 0)
  const vendidoSinChips = vendidoConChips - vendidoChips
  const cuadresConVenta = new Set(ventasVisibles.map((item) => item.idCuadre)).size

  async function verDetalleCuadre(ruta) {
    if (!ruta.idCuadre) return
    setCargandoDetalle(true)
    setDetalle(null)
    try {
      const data = await api(`/api/auth/almacen/cuadres/${ruta.idCuadre}`, { headers: { Authorization: `Bearer ${session.token}` } })
      setDetalle(data)
    } catch (err) { setError(err.message) } finally { setCargandoDetalle(false) }
  }

  async function verSaldoRuta(ruta) {
    setRutaSaldo(ruta)
    setSaldoRuta(null)
    setCargandoSaldoRuta(true)
    setError('')
    try {
      const data = await api(`/api/auth/almacen/cuadres/rutas/${ruta.idRuta}/saldo`, { headers: { Authorization: `Bearer ${session.token}` } })
      setSaldoRuta(saldoConNombresVisibles(data))
    } catch (err) { setError(err.message); setRutaSaldo(null) } finally { setCargandoSaldoRuta(false) }
  }

  function abrirCuadreAlmacen(ruta) {
    if (fecha !== hoy) { setError('El cuadre asistido solo se puede registrar para la fecha de hoy.'); return }
    if (!ruta.idVendedor) { setError('Esta ruta no tiene un vendedor asignado para realizar el cuadre.'); return }
    setError('')
    setRutaParaCuadre(ruta)
  }

  async function verDetallePreliminar(item) {
    setCargandoPreliminar(true)
    setDetallePreliminar(null)
    setError('')
    try {
      setDetallePreliminar(await api(`/api/auth/almacen/cuadres-preliminares/${item.idCuadreEnRuta}`, { headers: { Authorization: `Bearer ${session.token}` } }))
    } catch (err) { setError(err.message) } finally { setCargandoPreliminar(false) }
  }

  async function aprobarPreliminar() {
    if (!detallePreliminar || !window.confirm('Se aplicará exactamente la versión enviada por el vendedor. ¿Aprobar cuadre?')) return
    setProcesandoPreliminar(true)
    setError('')
    try {
      await api(`/api/auth/almacen/cuadres-preliminares/${detallePreliminar.idCuadreEnRuta}/aprobar`, { method: 'POST', headers: { Authorization: `Bearer ${session.token}` } })
      setDetallePreliminar(null)
      setRecarga((valor) => valor + 1)
    } catch (err) { setError(err.message) } finally { setProcesandoPreliminar(false) }
  }

  return <section className="warehouse-cuadre-module">
    <aside className="cuadre-route-sidebar">
      <div className="seller-sidebar-heading"><p>RUTAS Y CUADRES</p><span>{rutasCuadre.length}</span></div>
      <div className="seller-search"><span>⌕</span><input type="search" placeholder="Buscar ruta o técnico…" value={busqueda} onChange={(event) => setBusqueda(event.target.value)} /></div>
      <button className={`seller-all ${!idRuta ? 'active' : ''}`} type="button" onClick={() => setIdRuta('')}><span>Todas las rutas</span>{pendientesRevision > 0 && <b>{pendientesRevision}</b>}</button>
      <div className="cuadre-route-list">
        {cargando ? <div className="seller-loading">Consultando…</div> : rutasBuscadas.map((ruta) => <button className={`${Number(idRuta) === ruta.idRuta ? 'active' : ''} ${pendientesPorRuta[ruta.idRuta] > 0 ? 'has-pending-cashup' : ''} ${rutasModificadas.has(ruta.idRuta) ? 'has-modified-cashup' : ''}`} type="button" key={ruta.idRuta} onClick={() => setIdRuta(String(ruta.idRuta))}><div><strong>{ruta.ruta}</strong><small>{ruta.tecnico}</small></div>{pendientesPorRuta[ruta.idRuta] > 0 && <b>{pendientesPorRuta[ruta.idRuta]}</b>}</button>)}
      </div>
    </aside>

    <section className="warehouse-cuadres-content">
      <header className="warehouse-cuadres-heading"><div><p>CONTROL DIARIO</p><h2>{vistaCuadres === 'preliminares' ? 'Cuadres pendientes de revisión' : rutaSeleccionada ? rutaSeleccionada.ruta : 'Cuadres de todas las rutas'}</h2><span>{vistaCuadres === 'preliminares' ? 'Versiones enviadas por vendedores antes de afectar el inventario definitivo.' : rutaSeleccionada ? rutaSeleccionada.tecnico : 'Seguimiento de vendedores que realizaron o no su cuadre.'}</span></div><div className="cuadre-date-control"><label>Fecha<input type="date" value={fecha} max={hoy} onChange={(event) => { setFecha(event.target.value); setIdRuta('') }} /></label><button type="button" onClick={() => { setFecha(hoy); setIdRuta('') }}>Hoy</button></div></header>
      <div className="cuadre-view-switch"><button className={vistaCuadres === 'preliminares' ? 'active' : ''} type="button" onClick={() => setVistaCuadres('preliminares')}>Pendientes de aprobación {pendientesRevision > 0 && <b>{pendientesRevision}</b>}</button><button className={vistaCuadres === 'rutas' ? 'active' : ''} type="button" onClick={() => setVistaCuadres('rutas')}>Estado por rutas</button></div>
      <div className="cuadre-sales-summary">
        <article><span>CUADRE SIN CHIPS</span><strong>{cargandoVentas ? '…' : money.format(vendidoSinChips)}</strong><small>Vendido {fecha === hoy ? 'hoy' : 'en la fecha'} sin contar chips</small></article>
        <article className="with-chips"><span>CUADRE CON CHIPS</span><strong>{cargandoVentas ? '…' : money.format(vendidoConChips)}</strong><small>{cargandoVentas ? 'Calculando…' : `Incluye ${money.format(vendidoChips)} en chips`}</small></article>
        <p>{errorVentas ? `No se pudo calcular lo vendido: ${errorVentas}` : `${rutaSeleccionada ? rutaSeleccionada.ruta : 'Todas las rutas'} · ${cuadresConVenta} cuadre(s) definitivo(s). Los preliminares pendientes se suman al aprobarlos.`}</p>
      </div>
      {vistaCuadres === 'rutas' && <div className="warehouse-cuadre-toolbar"><div><button className={filtro === 'todos' ? 'active' : ''} type="button" onClick={() => setFiltro('todos')}>Todos <b>{rutasCuadre.length}</b></button><button className={filtro === 'realizados' ? 'active' : ''} type="button" onClick={() => setFiltro('realizados')}>Realizados <b>{realizadas}</b></button><button className={filtro === 'sin_cuadre' ? 'active' : ''} type="button" onClick={() => setFiltro('sin_cuadre')}>Sin cuadre <b>{pendientes}</b></button></div><span>{fecha === hoy ? 'Estado de hoy' : `Fecha consultada: ${fecha}`}</span></div>}
      {error && <div className="warehouse-orders-message warehouse-orders-message--error">{error}</div>}
      {cargando ? <div className="warehouse-orders-message">Consultando cuadres…</div> : vistaCuadres === 'preliminares' ? (preliminaresVisibles.length === 0 ? <section className="cashup-empty-state"><div className="cashup-empty-icon" aria-hidden="true"><span>✓</span></div><p>CONTROL DE CUADRES</p><h3>{idRuta ? 'Esta ruta todavía no envió su cuadre' : 'Aún no se enviaron cuadres'}</h3><span>{idRuta ? `${rutaSeleccionada?.ruta || 'La ruta seleccionada'} no tiene un cuadre preliminar para la fecha consultada.` : 'No existen cuadres pendientes de revisión para la fecha seleccionada.'}</span><div><b>{fecha === hoy ? 'HOY' : 'FECHA CONSULTADA'}</b><time>{new Intl.DateTimeFormat('es-BO', { dateStyle: 'long' }).format(new Date(`${fecha}T12:00:00`))}</time></div><small>Cuando un vendedor envíe su cuadre, aparecerá automáticamente en este espacio.</small></section> : <div className="preliminary-cashup-list">{preliminaresVisibles.map((item) => <article key={item.idCuadreEnRuta}><div className="preliminary-cashup-id"><span>PRELIMINAR</span><strong>#{item.idCuadreEnRuta}</strong></div><div className="preliminary-cashup-person"><small>{item.ruta}</small><strong>{item.tecnico}</strong><span>{dateTime.format(new Date(item.fecha))}</span></div><dl><div><dt>Total declarado</dt><dd>{money.format(item.total)}</dd></div><div><dt>Estado</dt><dd>{item.estadoAprobado === 1 ? 'Pendiente de almacén' : item.modificado ? 'Aprobado con cambios' : 'Aprobado sin cambios'}</dd></div></dl><span className={`cuadre-route-status ${item.estadoAprobado === 1 ? 'missing' : 'done'}`}>{item.estadoAprobado === 1 ? 'PENDIENTE' : item.modificado ? 'MODIFICADO' : 'APROBADO'}</span><button type="button" onClick={() => verDetallePreliminar(item)}>Ver detalle</button></article>)}</div>) : rutasVisibles.length === 0 ? <div className="warehouse-orders-message">No existen rutas con este filtro.</div> : <div className="warehouse-cuadre-list">
        {rutasVisibles.map((ruta) => <article className={`warehouse-cuadre-row ${ruta.realizoCuadre ? 'completed' : 'pending'}`} key={ruta.idRuta}><div className="cuadre-route-number"><span>Ruta</span><strong>#{ruta.idRuta}</strong></div><div className="cuadre-route-person"><small>{ruta.ruta}</small><strong>{ruta.tecnico}</strong><span>{ruta.idVendedor ? `Vendedor #${ruta.idVendedor}` : 'Sin vendedor asignado'}</span></div>{ruta.realizoCuadre ? <><dl><div><dt>Cuadre</dt><dd>#{ruta.idCuadre}</dd></div><div><dt>Registrado</dt><dd>{dateTime.format(new Date(ruta.fecha))}</dd></div><div><dt>Total vendido</dt><dd>{money.format(ruta.total)}</dd></div></dl><span className="cuadre-route-status done">REALIZADO</span><button type="button" onClick={() => verDetalleCuadre(ruta)}>Ver detalle</button></> : <><div className="cuadre-not-done"><strong>Sin cuadre</strong><span>No registró cuadre en esta fecha.</span></div><span className="cuadre-route-status missing">PENDIENTE</span><div className="cuadre-pending-actions"><button type="button" onClick={() => verSaldoRuta(ruta)}>ⓘ Ver saldo</button><button className="primary" type="button" disabled={fecha !== hoy || !ruta.idVendedor} onClick={() => abrirCuadreAlmacen(ruta)}>Realizar cuadre</button></div></>}</article>)}
      </div>}
    </section>

    {(detalle || cargandoDetalle) && <div className="order-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !cargandoDetalle) setDetalle(null) }}><section className="order-dialog cuadre-detail-dialog" role="dialog" aria-modal="true"><div className="order-dialog-head"><div><p>DETALLE DE CUADRE</p><h2>Cuadre #{detalle?.idCuadre}</h2></div><button type="button" onClick={() => setDetalle(null)}>×</button></div>{cargandoDetalle ? <div className="orders-message">Consultando detalle…</div> : <div className="cuadre-detail-content"><div className="cuadre-detail-summary"><div><span>Ruta</span><strong>{detalle.ruta}</strong></div><div><span>Técnico</span><strong>{detalle.tecnico}</strong></div><div><span>Fecha</span><strong>{dateTime.format(new Date(detalle.fecha))}</strong></div><div><span>Total vendido</span><strong>{money.format(detalle.total)}</strong></div></div>{detalle.observacion && <div className="detail-observation"><span>Observación</span><strong>{detalle.observacion}</strong></div>}<div className="cuadre-detail-products">{detalle.productos.map((producto) => <article key={producto.idProducto}><header><div><span>{producto.tipoProducto || 'Producto'}</span><strong>{producto.producto}</strong></div><b>{money.format(producto.totalVendido)}</b></header><dl><div><dt>Saldo anterior</dt><dd>{integer.format(producto.saldoAnterior)}</dd></div><div><dt>Ingresó como sobrante</dt><dd>{integer.format(producto.sobranteIngresado)}</dd></div><div><dt>Vendido</dt><dd>{integer.format(producto.vendido)}</dd></div><div><dt>Saldo actual</dt><dd>{integer.format(producto.saldoActual)}</dd></div></dl><div className="cuadre-detail-strips"><div><span>TIRAS REGISTRADAS</span><b>{producto.tiras.length}</b></div>{producto.tiras.length ? producto.tiras.map((tira, index) => <div className="cuadre-detail-strip" key={tira.idSaldoCuadre}><span>Tira {index + 1}</span><strong>{integer.format(tira.cantidad)} unidad(es)</strong><code>{tira.codigoInicio} — {tira.codigoFinal}</code></div>) : <small>Este producto no registró tiras sobrantes.</small>}</div></article>)}</div></div>}</section></div>}
    {(detallePreliminar || cargandoPreliminar) && <div className="order-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !cargandoPreliminar && !procesandoPreliminar) setDetallePreliminar(null) }}><section className="order-dialog preliminary-detail-dialog" role="dialog" aria-modal="true"><div className="order-dialog-head"><div><p>VERSIÓN ORIGINAL DEL VENDEDOR</p><h2>Cuadre preliminar #{detallePreliminar?.idCuadreEnRuta}</h2></div><button type="button" disabled={procesandoPreliminar} onClick={() => setDetallePreliminar(null)}>×</button></div>{cargandoPreliminar ? <div className="orders-message">Consultando preliminar…</div> : <div className="preliminary-detail-content"><div className="cuadre-detail-summary"><div><span>Ruta</span><strong>{detallePreliminar.ruta}</strong></div><div><span>Técnico</span><strong>{detallePreliminar.tecnico}</strong></div><div><span>Enviado</span><strong>{dateTime.format(new Date(detallePreliminar.fecha))}</strong></div><div><span>Total declarado</span><strong>{money.format(detallePreliminar.total)}</strong></div></div>{detallePreliminar.observacion && <div className="detail-observation"><span>Observación del vendedor</span><strong>{detallePreliminar.observacion}</strong></div>}<section className="preliminary-version"><header><div><span>HISTORIAL INALTERABLE</span><strong>Versión ingresada por el vendedor</strong></div><b>{detallePreliminar.productos.length} producto(s)</b></header><div className="preliminary-products-table"><div className="head"><span>Producto</span><span>Saldo anterior</span><span>Sobrante</span><span>Vendido</span><span>Total</span></div>{detallePreliminar.productos.map((producto) => <div key={producto.idProducto}><strong>{producto.producto}</strong><span>{integer.format(producto.itemsSobrantes + producto.itemsVendidos)}</span><span>{integer.format(producto.itemsSobrantes)}</span><span>{integer.format(producto.itemsVendidos)}</span><b>{money.format(producto.totalVendidos)}</b></div>)}</div><div className="preliminary-strips"><h4>Tiras y valores enviados</h4>{tirasPreliminar.map((tira) => <div key={`${tira.idProducto}-${tira.numero}`}><span>{tira.modo === 'tigo_money' ? 'Tigo Money' : tira.modo === 'chip_cantidad' ? 'Chips por cantidad' : `Tira ${tira.numero}`}</span><strong>{integer.format(tira.cantidad)} unidad(es)</strong><code>{tira.inicio} — {tira.final}</code>{tira.modo === 'tigo_money' && <b>Efectivización: {integer.format(tira.efectivizacion)}</b>}</div>)}</div></section>{detallePreliminar.modificado && detallePreliminar.versionDefinitiva && <section className="preliminary-version modified"><header><div><span>VERSIÓN DEFINITIVA</span><strong>Modificada por {detallePreliminar.aprobadoPor}</strong></div><b>Cuadre #{detallePreliminar.idCuadre}</b></header><div className="preliminary-products-table"><div className="head"><span>Producto</span><span>Saldo anterior</span><span>Sobrante</span><span>Vendido</span><span>Total</span></div>{detallePreliminar.versionDefinitiva.productos.map((producto) => <div key={producto.idProducto}><strong>{producto.producto}</strong><span>{integer.format(producto.saldoAnterior)}</span><span>{integer.format(producto.sobranteIngresado)}</span><span>{integer.format(producto.vendido)}</span><b>{money.format(producto.totalVendido)}</b></div>)}</div></section>}{detallePreliminar.estadoAprobado === 1 ? <div className="preliminary-actions"><button type="button" onClick={() => { setPreliminarModificar(detallePreliminar); setDetallePreliminar(null) }}>Modificar y aprobar</button><button className="primary" type="button" disabled={procesandoPreliminar} onClick={aprobarPreliminar}>{procesandoPreliminar ? 'Aprobando…' : 'Aprobar sin cambios'}</button></div> : <div className={`preliminary-approved-note ${detallePreliminar.modificado ? 'modified' : ''}`}><strong>{detallePreliminar.modificado ? 'Aprobado con modificaciones' : 'Aprobado sin modificaciones'}</strong><span>{detallePreliminar.aprobadoPor}{detallePreliminar.fechaAprobacion ? ` · ${dateTime.format(new Date(detallePreliminar.fechaAprobacion))}` : ''}</span></div>}</div>}</section></div>}
    {(rutaSaldo || cargandoSaldoRuta) && <div className="order-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !cargandoSaldoRuta) setRutaSaldo(null) }}><section className="order-dialog route-balance-dialog" role="dialog" aria-modal="true"><div className="order-dialog-head"><div><p>SALDO ACTUAL DE RUTA</p><h2>{rutaSaldo?.ruta}</h2><span>{rutaSaldo?.tecnico}</span></div><button type="button" onClick={() => setRutaSaldo(null)}>×</button></div>{cargandoSaldoRuta ? <div className="orders-message">Consultando saldo…</div> : <div className="warehouse-route-balance"><div className="cuadre-detail-summary"><div><span>Productos</span><strong>{integer.format(saldoRuta.totalProductos)}</strong></div><div><span>Unidades</span><strong>{integer.format(saldoRuta.totalUnidades)}</strong></div><div><span>Valor total</span><strong>{money.format(saldoRuta.valorTotal)}</strong></div></div><div className="route-balance-table"><div className="route-balance-row head"><span>Producto</span><span>Cantidad</span></div>{saldoRuta.productos.map((item) => <div className="route-balance-row" key={item.idProducto}><strong>{item.producto}</strong><b>{integer.format(item.cantidad)}</b></div>)}</div></div>}</section></div>}
    {rutaParaCuadre && <div className="order-overlay warehouse-cashup-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setRutaParaCuadre(null) }}><section className="order-dialog warehouse-cashup-dialog" role="dialog" aria-modal="true"><div className="order-dialog-head"><div><p>REALIZAR CUADRE POR ALMACÉN</p><h2>{rutaParaCuadre.ruta}</h2><span>{rutaParaCuadre.tecnico}</span></div><button type="button" onClick={() => setRutaParaCuadre(null)}>×</button></div><MyCuadrePanel key={rutaParaCuadre.idRuta} session={session} rutaObjetivo={rutaParaCuadre} onCompletado={() => setRecarga((valor) => valor + 1)} /></section></div>}
    {preliminarModificar && <div className="order-overlay warehouse-cashup-overlay" role="presentation"><section className="order-dialog warehouse-cashup-dialog" role="dialog" aria-modal="true"><div className="order-dialog-head"><div><p>MODIFICAR VERSIÓN DEL VENDEDOR</p><h2>{preliminarModificar.ruta}</h2><span>La versión original #{preliminarModificar.idCuadreEnRuta} se conservará sin cambios.</span></div><button type="button" onClick={() => setPreliminarModificar(null)}>×</button></div><MyCuadrePanel key={`mod-${preliminarModificar.idCuadreEnRuta}`} session={session} rutaObjetivo={preliminarModificar} endpointFinalizarOverride={`/api/auth/almacen/cuadres-preliminares/${preliminarModificar.idCuadreEnRuta}/modificar-aprobar`} onCompletado={() => { setRecarga((valor) => valor + 1) }} /></section></div>}
  </section>
}

function WarehouseClosingPanel({ session }) {
  const hoy = new Date().toISOString().slice(0, 10)
  const [fecha, setFecha] = useState(hoy)
  const [productos, setProductos] = useState([])
  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState('')
  const [mensaje, setMensaje] = useState('')
  const [estadoCierre, setEstadoCierre] = useState(null)
  const [observacion, setObservacion] = useState('')
  const [guardando, setGuardando] = useState(false)
  const [anchosColumnas, setAnchosColumnas] = useState([72, 155, 92, 105, 118, 108, 124, 82, 100, 96, 112, 105, 120, 82, 100, 92, 108, 104, 120])
  const money = new Intl.NumberFormat('es-BO', { style: 'currency', currency: 'BOB' })
  const number = new Intl.NumberFormat('es-BO', { maximumFractionDigits: 2 })

  useEffect(() => {
    let activo = true
    setCargando(true)
    setError('')
    setMensaje('')
    Promise.all([
      api(`/api/auth/almacen/cierre?fecha=${fecha}`, { headers: { Authorization: `Bearer ${session.token}` } }),
      api(`/api/auth/almacen/cierre/estado?fecha=${fecha}`, { headers: { Authorization: `Bearer ${session.token}` } }),
    ])
      .then(([data, estado]) => { if (activo) { setProductos(data); setEstadoCierre(estado) } })
      .catch((err) => { if (activo) { setProductos([]); setEstadoCierre(null); setError(err.message) } })
      .finally(() => { if (activo) setCargando(false) })
    return () => { activo = false }
  }, [fecha, session.token])

  const productosGenerales = productos.filter((item) => Number(item.saldoDiaHoy || 0) > 0)
  const productosTigo = productos.filter((item) => Number(item.saldoDiaHoyTigo || 0) > 0)
  const sumar = (filas, ...campos) => filas.reduce((total, item) => total + campos.reduce((suma, campo) => suma + Number(item[campo] || 0), 0), 0)
  const sumarCierres = (campoGeneral, campoTigo) => sumar(productosGenerales, campoGeneral) + sumar(productosTigo, campoTigo)
  const resumen = [
    { label: 'Saldo anterior', value: sumarCierres('totalSaldoDiaAnterior', 'totalSaldoDiaAnteriorTigo'), detail: sumarCierres('saldoDiaAnterior', 'saldoDiaAnteriorTigo') },
    { label: 'Compras del día', value: sumarCierres('totalCompraDia', 'totalCompraDiaTigo'), detail: sumarCierres('compraDia', 'compraDiaTigo') },
    { label: 'Devoluciones', value: sumar(productosGenerales, 'totalDevolucionIngreso'), detail: sumar(productosGenerales, 'devolucionIngreso') },
    { label: 'Ventas del día', value: sumar(productosGenerales, 'totalVentaDia'), detail: sumar(productosGenerales, 'ventaDia') },
    { label: 'Saldo final', value: sumarCierres('totalSaldoDiaHoy', 'totalSaldoDiaHoyTigo'), detail: sumarCierres('saldoDiaHoy', 'saldoDiaHoyTigo') },
  ]
  const columnasCierre = [
    ['idProducto', 'Id Producto', 'numero'], ['nombre', 'Nombre', 'texto'], ['precioVenta', 'Precio venta', 'dinero'],
    ['saldoDiaAnterior', 'Saldo día anterior', 'numero'], ['totalSaldoDiaAnterior', 'Total saldo anterior', 'dinero'],
    ['saldoDiaAnteriorTigo', 'Saldo anterior TIGO', 'numero'], ['totalSaldoDiaAnteriorTigo', 'Total saldo anterior TIGO', 'dinero'],
    ['compraDia', 'Compra día', 'numero'], ['totalCompraDia', 'Total compra día', 'dinero'],
    ['compraDiaTigo', 'Compra día TIGO', 'numero'], ['totalCompraDiaTigo', 'Total compra día TIGO', 'dinero'],
    ['devolucionIngreso', 'Devolución ingreso', 'numero'], ['totalDevolucionIngreso', 'Total devolución ingreso', 'dinero'],
    ['ventaDia', 'Venta día', 'numero'], ['totalVentaDia', 'Total venta día', 'dinero'],
    ['saldoDiaHoy', 'Saldo día hoy', 'numero'], ['totalSaldoDiaHoy', 'Total saldo día hoy', 'dinero'],
    ['saldoDiaHoyTigo', 'Saldo día hoy TIGO', 'numero'], ['totalSaldoDiaHoyTigo', 'Total saldo día hoy TIGO', 'dinero'],
  ]
  const formatearDato = (valor, tipo) => tipo === 'dinero' ? money.format(Number(valor || 0)) : tipo === 'numero' ? number.format(Number(valor || 0)) : (valor ?? '')
  const columnasBase = columnasCierre.slice(0, 3)
  const columnasTigo = [...columnasBase, ...columnasCierre.filter(([campo]) => /tigo/i.test(campo))]
  const columnasGenerales = [...columnasBase, ...columnasCierre.slice(3).filter(([campo]) => !/tigo/i.test(campo))]
  const iniciarCambioAncho = (indice, event) => {
    event.preventDefault()
    event.stopPropagation()
    const inicioX = event.clientX
    const anchoInicial = anchosColumnas[indice]
    const mover = (movimiento) => setAnchosColumnas((actuales) => actuales.map((ancho, posicion) => posicion === indice ? Math.max(58, Math.min(320, anchoInicial + movimiento.clientX - inicioX)) : ancho))
    const terminar = () => {
      window.removeEventListener('pointermove', mover)
      window.removeEventListener('pointerup', terminar)
      document.body.classList.remove('closing-resizing')
    }
    document.body.classList.add('closing-resizing')
    window.addEventListener('pointermove', mover)
    window.addEventListener('pointerup', terminar, { once: true })
  }

  const guardarCierre = async () => {
    if (estadoCierre?.existe || guardando || productos.length === 0) return
    if (!window.confirm(`¿Está seguro de guardar definitivamente el cierre de almacén del ${fecha}?`)) return
    setGuardando(true)
    setError('')
    setMensaje('')
    try {
      const cierre = await api('/api/auth/almacen/cierre', {
        method: 'POST',
        headers: { Authorization: `Bearer ${session.token}` },
        body: JSON.stringify({ fecha, observacion: observacion.trim() }),
      })
      setEstadoCierre({ existe: true, ...cierre, observacion: observacion.trim() })
      setMensaje(`Cierre #${cierre.idCierreAlmacen} registrado satisfactoriamente con ${cierre.cantidadProductos} producto(s).`)
    } catch (err) {
      setError(err.message)
      try {
        const estado = await api(`/api/auth/almacen/cierre/estado?fecha=${fecha}`, { headers: { Authorization: `Bearer ${session.token}` } })
        setEstadoCierre(estado)
      } catch {
        // Se conserva el error original del guardado.
      }
    } finally {
      setGuardando(false)
    }
  }

  return <section className="warehouse-closing-panel">
    <header className="warehouse-closing-head"><div><p>CONTROL DIARIO</p><h2>CIERRE DE ALMACÉN</h2><span>Resumen consolidado de existencias y movimientos por producto.</span></div><label>Fecha<input type="date" value={fecha} max={hoy} onChange={(event) => setFecha(event.target.value)} /></label></header>
    {error && <div className="warehouse-orders-message warehouse-orders-message--error">{error}</div>}
    {mensaje && <div className="warehouse-orders-message warehouse-orders-message--success">{mensaje}</div>}
    {cargando ? <div className="warehouse-orders-message">Consultando cierre de almacén…</div> : productos.length === 0 ? <section className="cashup-empty-state"><div className="cashup-empty-icon"><span>—</span></div><p>CIERRE DE ALMACÉN</p><h3>No existen movimientos para esta fecha</h3><span>El procedimiento no devolvió productos para el día seleccionado.</span></section> : <>
      <div className="closing-kpis">{resumen.map((item, index) => <article className={index === resumen.length - 1 ? 'primary' : ''} key={item.label}><span>{item.label}</span><strong>{money.format(item.value)}</strong><small>{number.format(item.detail)} unidad(es)</small></article>)}</div>
      <div className="closing-table-wrap">
        <div className="closing-raw-title"><div><strong>Resultado completo del procedimiento</strong><span>{columnasCierre.length} campos · {productos.length} producto(s)</span></div><small>Arrastra el borde derecho de un encabezado para cambiar su ancho</small></div>
        {[{ titulo: 'TIGO', columnas: columnasTigo, filas: productosTigo, clase: 'tigo' }, { titulo: 'MOVIMIENTOS GENERALES', columnas: columnasGenerales, filas: productosGenerales, clase: 'general' }].map((bloque) => <section className={`closing-excel-block ${bloque.clase}`} key={bloque.titulo}>
          <header><strong>{bloque.titulo}</strong><span>{bloque.columnas.length} columnas</span></header>
          <div className="closing-excel-scroll"><table className="closing-excel-table" style={{ '--first-column-width': `${anchosColumnas[0]}px` }}>
            <colgroup>{bloque.columnas.map(([campo]) => { const indice = columnasCierre.findIndex(([actual]) => actual === campo); return <col style={{ width: `${anchosColumnas[indice]}px` }} key={campo} /> })}</colgroup>
            <thead><tr>{bloque.columnas.map(([campo, etiqueta]) => { const indice = columnasCierre.findIndex(([actual]) => actual === campo); return <th key={campo}><span>{etiqueta}</span><button type="button" aria-label={`Cambiar ancho de ${etiqueta}`} onPointerDown={(event) => iniciarCambioAncho(indice, event)} /></th> })}</tr></thead>
            <tbody>{bloque.filas.length > 0 ? bloque.filas.map((item) => <tr key={item.idProducto}>{bloque.columnas.map(([campo, , tipo]) => <td className={`${tipo === 'dinero' ? 'money' : ''} ${campo === 'nombre' ? 'product' : ''}`} key={campo}>{formatearDato(item[campo], tipo)}</td>)}</tr>) : <tr><td colSpan={bloque.columnas.length}>Sin productos con saldo mayor a cero.</td></tr>}</tbody>
          </table></div>
        </section>)}
      </div>
      <section className={`closing-save-panel ${estadoCierre?.existe ? 'completed' : ''}`}>
        <div className="closing-save-copy">
          <span>{estadoCierre?.existe ? 'CIERRE REGISTRADO' : 'GUARDAR CIERRE'}</span>
          <strong>{estadoCierre?.existe ? `Cierre #${estadoCierre.idCierreAlmacen}` : 'Confirmar existencias del día'}</strong>
          <small>{estadoCierre?.existe ? `${estadoCierre.cantidadProductos} producto(s) guardados para esta fecha.` : 'La cabecera y todos los detalles se guardarán juntos en una sola transacción.'}</small>
        </div>
        {!estadoCierre?.existe && <label className="closing-observation"><span>Observación</span><input type="text" maxLength={28} value={observacion} onChange={(event) => setObservacion(event.target.value)} placeholder="Observación opcional" /><small>{observacion.length}/28</small></label>}
        <div className="closing-save-actions">
          {estadoCierre?.existe && <button className="secondary" type="button" onClick={() => window.print()}>Imprimir</button>}
          <button className="primary" type="button" disabled={estadoCierre?.existe || guardando || productos.length === 0} onClick={guardarCierre}>{guardando ? 'Guardando…' : estadoCierre?.existe ? 'Cierre ya guardado' : 'Guardar cierre'}</button>
        </div>
      </section>
      <footer className="closing-footnote">Datos obtenidos directamente de <code>sp_ObtenerCierreAlmacen_</code> para {fecha}.</footer>
    </>}
  </section>
}

function WarehouseDashboard({ session, onLogout }) {
  const { usuario } = session
  const scannerStorageKey = `login-general-scanner-${usuario.sucursal.id}-${usuario.id}`
  const initials = usuario.nombre.split(/\s+/).slice(0, 2).map((part) => part[0]).join('').toUpperCase()
  const hoy = new Date().toISOString().slice(0, 10)
  const inicioMes = `${hoy.slice(0, 7)}-01`
  const inicioHistorico = '2000-01-01'
  const [rutas, setRutas] = useState([])
  const [idRuta, setIdRuta] = useState('')
  const [busqueda, setBusqueda] = useState('')
  const [fechaDesde, setFechaDesde] = useState(inicioHistorico)
  const [fechaHasta, setFechaHasta] = useState(hoy)
  const [modoPedidos, setModoPedidos] = useState('pendientes')
  const [buscarPedidoId, setBuscarPedidoId] = useState('')
  const [pedidos, setPedidos] = useState([])
  const [cargandoRutas, setCargandoRutas] = useState(true)
  const [cargandoPedidos, setCargandoPedidos] = useState(false)
  const [errorAlmacen, setErrorAlmacen] = useState('')
  const [mensajeAlmacen, setMensajeAlmacen] = useState('')
  const [pedidoSeleccionado, setPedidoSeleccionado] = useState(null)
  const [detallePedido, setDetallePedido] = useState([])
  const [productosAsignados, setProductosAsignados] = useState([])
  const [vistaDetalle, setVistaDetalle] = useState('pedido')
  const [cargandoDetalle, setCargandoDetalle] = useState(false)
  const [fechaEntrega, setFechaEntrega] = useState(hoy)
  const [moduloAlmacen, setModuloAlmacen] = useState('pedidos')
  const panelesStorageKey = `login-general-paneles-almacen-${usuario.id}`
  const [anchosPaneles, setAnchosPaneles] = useState(() => {
    try {
      const guardados = JSON.parse(localStorage.getItem(`login-general-paneles-almacen-${usuario.id}`) || '{}')
      return { menu: Number(guardados.menu) || 230, rutas: Number(guardados.rutas) || 330, menuOculto: Boolean(guardados.menuOculto) }
    } catch { return { menu: 230, rutas: 330, menuOculto: false } }
  })
  const [tutorialAbierto, setTutorialAbierto] = useState(false)
  const [cuadresRealizadosHoy, setCuadresRealizadosHoy] = useState(0)
  const [cuadresPendientesHoy, setCuadresPendientesHoy] = useState(0)
  const [rutaNueva, setRutaNueva] = useState(null)
  const [notificacionPedido, setNotificacionPedido] = useState(null)
  const [vinculoScanner, setVinculoScanner] = useState(null)
  const [qrVinculoScanner, setQrVinculoScanner] = useState('')
  const [creandoVinculo, setCreandoVinculo] = useState(false)
  const [detalleEscaneo, setDetalleEscaneo] = useState(null)
  const [modoTiraPedido, setModoTiraPedido] = useState('rango')
  const [lecturasTiraPedido, setLecturasTiraPedido] = useState([])
  const [asignacionesPedido, setAsignacionesPedido] = useState({})
  const [scannerPedidoError, setScannerPedidoError] = useState('')
  const [listaScannerCerrada, setListaScannerCerrada] = useState(false)
  const [validandoTiraPedido, setValidandoTiraPedido] = useState(false)
  const [ingresoManualPedido, setIngresoManualPedido] = useState(false)
  const [imeiManualPrimero, setImeiManualPrimero] = useState('')
  const [imeiManualUltimo, setImeiManualUltimo] = useState('')
  const [cantidadManualTira, setCantidadManualTira] = useState('')
  const [imeisManuales, setImeisManuales] = useState('')
  const [imeiManualPrimeroValidado, setImeiManualPrimeroValidado] = useState(false)
  const [imeiManualUltimoValidado, setImeiManualUltimoValidado] = useState(false)
  const [imeisManualesConfirmados, setImeisManualesConfirmados] = useState([])
  const [validandoImeiManual, setValidandoImeiManual] = useState(false)
  const [validandoTigoMoney, setValidandoTigoMoney] = useState(null)
  const [tigoMoneyValidado, setTigoMoneyValidado] = useState({})
  const [editandoPedidoAlmacen, setEditandoPedidoAlmacen] = useState(false)
  const [cantidadesPedidoAlmacen, setCantidadesPedidoAlmacen] = useState({})
  const [comentarioPedidoAlmacen, setComentarioPedidoAlmacen] = useState('')
  const [guardandoPedidoAlmacen, setGuardandoPedidoAlmacen] = useState(false)
  const [promedioPedidoAlmacenVisible, setPromedioPedidoAlmacenVisible] = useState(false)
  const [promediosPedidoAlmacen, setPromediosPedidoAlmacen] = useState([])
  const [cargandoPromedioPedidoAlmacen, setCargandoPromedioPedidoAlmacen] = useState(false)
  const [promedioPedidoAlmacenError, setPromedioPedidoAlmacenError] = useState('')
  const [saldoPedidoAlmacenVisible, setSaldoPedidoAlmacenVisible] = useState(false)
  const [saldoPedidoAlmacen, setSaldoPedidoAlmacen] = useState(null)
  const [cargandoSaldoPedidoAlmacen, setCargandoSaldoPedidoAlmacen] = useState(false)
  const [saldoPedidoAlmacenError, setSaldoPedidoAlmacenError] = useState('')
  const [imeisRevisionTiraPedido, setImeisRevisionTiraPedido] = useState(null)
  const [pedidoDirectoAbierto, setPedidoDirectoAbierto] = useState(false)
  const [observacionPedidoDirecto, setObservacionPedidoDirecto] = useState('')
  const [tirasPedidoDirecto, setTirasPedidoDirecto] = useState([])
  const [modoPedidoDirecto, setModoPedidoDirecto] = useState('cantidad')
  const [primerImeiDirecto, setPrimerImeiDirecto] = useState('')
  const [ultimoImeiDirecto, setUltimoImeiDirecto] = useState('')
  const [cantidadTiraDirecta, setCantidadTiraDirecta] = useState('')
  const [imeisIndividualesDirectos, setImeisIndividualesDirectos] = useState('')
  const [errorPedidoDirecto, setErrorPedidoDirecto] = useState('')
  const [guardandoPedidoDirecto, setGuardandoPedidoDirecto] = useState(false)
  const [efectivoTigoDirecto, setEfectivoTigoDirecto] = useState('')
  const [validandoTigoDirecto, setValidandoTigoDirecto] = useState(false)
  const [tigoDirectoValidado, setTigoDirectoValidado] = useState(null)
  const [saldoRutaDirecto, setSaldoRutaDirecto] = useState(null)
  const [cargandoSaldoRutaDirecto, setCargandoSaldoRutaDirecto] = useState(false)
  const [errorSaldoRutaDirecto, setErrorSaldoRutaDirecto] = useState('')
  const consultaSaldoRutaDirectoRef = useRef(0)
  const [ahoraScanner, setAhoraScanner] = useState(() => Date.now())
  const rutaSeleccionada = rutas.find((ruta) => ruta.idRuta === Number(idRuta))
  const rutasFiltradas = rutas.filter((ruta) => `${ruta.ruta} ${ruta.tecnico}`.toLowerCase().includes(busqueda.trim().toLowerCase()))
  const pedidosFiltrados = buscarPedidoId.trim()
    ? pedidos.filter((pedido) => String(pedido.idPedido).includes(buscarPedidoId.trim().replace('#', '')))
    : pedidos
  const totalPendientes = idRuta
    ? (rutaSeleccionada?.pedidosPendientes ?? 0)
    : rutas.reduce((total, item) => total + item.pedidosPendientes, 0)
  const imeisAsignadosDetalle = (idDetalle) => (asignacionesPedido[idDetalle] || []).flatMap((tira) => tira.imeis)
  const detallesFisicos = detallePedido.filter((detalle) => detalle.idProducto !== 31)
  const detallesTigoMoney = detallePedido.filter((detalle) => detalle.idProducto === 31)
  const productosFisicosCompletos = detallePedido.length > 0
    && detallesFisicos.every((detalle) => imeisAsignadosDetalle(detalle.idDetalle).length === detalle.cantidad)
    && detallesTigoMoney.every((detalle) => Boolean(tigoMoneyValidado[detalle.idDetalle]))
  const tirasListaMaster = detallesFisicos.flatMap((detalle) => (asignacionesPedido[detalle.idDetalle] || []).map((tira) => ({
    ...tira,
    idDetalle: detalle.idDetalle,
    producto: detalle.producto,
    tipoProducto: detalle.tipoProducto,
  })))
  const tigoMoneyListaMaster = detallesTigoMoney.filter((detalle) => tigoMoneyValidado[detalle.idDetalle])
  const totalListaMaster = tirasListaMaster.reduce((total, tira) => total + tira.imeis.length, 0)
    + tigoMoneyListaMaster.reduce((total, detalle) => total + detalle.cantidad, 0)
  const totalProductosPedido = detallesFisicos.reduce((total, detalle) => total + detalle.cantidad, 0)
    + detallesTigoMoney.reduce((total, detalle) => total + detalle.cantidad, 0)
  const tirasConfirmadas = productosAsignados.reduce((tiras, item) => {
    const key = `${item.idDetalle}-${item.numeroTira}`
    const tira = tiras.find((actual) => actual.key === key)
    if (tira) tira.imeis.push(item.imei)
    else tiras.push({ key, numero: item.numeroTira, modo: item.modoTira, producto: item.producto, tipoProducto: item.tipoProducto, imeis: [item.imei] })
    return tiras
  }, [])
  const segundosScanner = vinculoScanner ? Math.max(0, Math.floor((new Date(vinculoScanner.expira).getTime() - ahoraScanner) / 1000)) : 0

  const iniciarRedimensionPanel = (panel, event) => {
    if (window.innerWidth <= 760) return
    event.preventDefault()
    const inicioX = event.clientX
    const anchoInicial = anchosPaneles[panel]
    document.body.classList.add('warehouse-resizing-panels')
    const mover = (movimiento) => {
      const minimo = panel === 'menu' ? 165 : 220
      const otroAncho = panel === 'menu' ? anchosPaneles.rutas : anchosPaneles.menu
      const maximoPreferido = panel === 'menu' ? 380 : 560
      const maximoDisponible = Math.max(minimo, window.innerWidth - otroAncho - 500)
      const nuevoAncho = Math.max(minimo, Math.min(maximoPreferido, maximoDisponible, anchoInicial + movimiento.clientX - inicioX))
      setAnchosPaneles((actual) => ({ ...actual, [panel]: Math.round(nuevoAncho) }))
    }
    const terminar = () => {
      document.body.classList.remove('warehouse-resizing-panels')
      window.removeEventListener('pointermove', mover)
      window.removeEventListener('pointerup', terminar)
    }
    window.addEventListener('pointermove', mover)
    window.addEventListener('pointerup', terminar, { once: true })
  }

  useEffect(() => {
    try { localStorage.setItem(panelesStorageKey, JSON.stringify(anchosPaneles)) } catch { /* El panel sigue funcionando sin persistencia. */ }
  }, [anchosPaneles, panelesStorageKey])

  useEffect(() => {
    const timer = setInterval(() => setAhoraScanner(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [])

  useEffect(() => {
    let activo = true
    Promise.all([
      api(`/api/auth/almacen/cuadres/rutas?fecha=${hoy}`, { headers: { Authorization: `Bearer ${session.token}` } }),
      api(`/api/auth/almacen/cuadres-preliminares?fecha=${hoy}`, { headers: { Authorization: `Bearer ${session.token}` } }),
    ]).then(([data, preliminares]) => { if (activo) { setCuadresRealizadosHoy(data.filter((item) => item.realizoCuadre).length); setCuadresPendientesHoy(preliminares.filter((item) => item.estadoAprobado === 1).length) } })
      .catch(() => null)
    return () => { activo = false }
  }, [hoy, session.token])

  useEffect(() => {
    let active = true
    const guardado = sessionStorage.getItem(scannerStorageKey)
    if (!guardado) return undefined
    try {
      const vinculoGuardado = JSON.parse(guardado)
      if (!vinculoGuardado?.token || new Date(vinculoGuardado.expira).getTime() <= Date.now()) {
        sessionStorage.removeItem(scannerStorageKey)
        return undefined
      }
      api(`/api/scanner/publico/${vinculoGuardado.token}`).then(async () => {
        const { default: QRCode } = await import('qrcode')
        const qr = await QRCode.toDataURL(vinculoGuardado.urlTelefono, { width: 320, margin: 2, errorCorrectionLevel: 'M', color: { dark: '#172f43', light: '#ffffff' } })
        if (active) {
          setVinculoScanner(vinculoGuardado)
          setQrVinculoScanner(qr)
        }
      }).catch(() => {
        sessionStorage.removeItem(scannerStorageKey)
        if (active) setScannerPedidoError('La vinculación anterior ya no existe. Genera un código QR nuevo.')
      })
    } catch {
      sessionStorage.removeItem(scannerStorageKey)
    }
    return () => { active = false }
  }, [scannerStorageKey])

  useEffect(() => {
    if (!vinculoScanner || segundosScanner > 0) return
    sessionStorage.removeItem(scannerStorageKey)
    queueMicrotask(() => {
      setVinculoScanner(null)
      setQrVinculoScanner('')
      setScannerPedidoError('La vinculación expiró. Genera un código QR nuevo.')
    })
  }, [segundosScanner, scannerStorageKey, vinculoScanner])

  useEffect(() => {
    if (!vinculoScanner || ingresoManualPedido) return undefined
    const controller = new AbortController()
    let active = true
    let reconnectTimer
    const conectar = async () => {
      try {
        await escucharScanner(session.token, vinculoScanner.token, controller.signal, (lectura) => {
          if (!active) return
          setLecturasTiraPedido((actuales) => {
            if (lectura.idPedido !== pedidoSeleccionado?.idPedido || lectura.idDetalle !== detalleEscaneo?.idDetalle) return actuales
            if (actuales.some((item) => item.codigo === lectura.codigo)) return actuales
            return [...actuales, { ...lectura, id: `${lectura.fecha}-${crypto.randomUUID()}` }]
          })
          setImeisRevisionTiraPedido(null)
          setListaScannerCerrada(false)
          setScannerPedidoError('')
        })
        if (active) reconnectTimer = setTimeout(conectar, 2000)
      } catch (err) {
        if (active && err.name !== 'AbortError') {
          if (esVinculacionNoDisponible(err)) {
            sessionStorage.removeItem(scannerStorageKey)
            setVinculoScanner(null)
            setQrVinculoScanner('')
            setScannerPedidoError('La vinculación dejó de existir. Genera un código QR nuevo.')
          } else reconnectTimer = setTimeout(conectar, 2500)
        }
      }
    }
    conectar()
    return () => { active = false; controller.abort(); clearTimeout(reconnectTimer) }
  }, [session.token, vinculoScanner, pedidoSeleccionado?.idPedido, detalleEscaneo?.idDetalle, ingresoManualPedido, scannerStorageKey])

  async function crearVinculoScanner() {
    setCreandoVinculo(true)
    setScannerPedidoError('')
    try {
      const creado = await api('/api/scanner/vinculaciones', { method: 'POST', headers: { Authorization: `Bearer ${session.token}` } })
      const basePublica = creado.publicUrl || window.location.origin
      const urlTelefono = `${basePublica.replace(/\/$/, '')}/scanner/${creado.token}`
      const { default: QRCode } = await import('qrcode')
      const qr = await QRCode.toDataURL(urlTelefono, { width: 320, margin: 2, errorCorrectionLevel: 'M', color: { dark: '#172f43', light: '#ffffff' } })
      setQrVinculoScanner(qr)
      const nuevoVinculo = { ...creado, urlTelefono }
      setVinculoScanner(nuevoVinculo)
      sessionStorage.setItem(scannerStorageKey, JSON.stringify(nuevoVinculo))
      return nuevoVinculo
    } catch (err) {
      setScannerPedidoError(err.message)
      return null
    } finally {
      setCreandoVinculo(false)
    }
  }

  async function cerrarVinculoScanner() {
    if (vinculoScanner) await api(`/api/scanner/vinculaciones/${vinculoScanner.token}`, { method: 'DELETE', headers: { Authorization: `Bearer ${session.token}` } }).catch(() => null)
    sessionStorage.removeItem(scannerStorageKey)
    setVinculoScanner(null)
    setQrVinculoScanner('')
    setDetalleEscaneo(null)
    setIngresoManualPedido(false)
    setImeiManualPrimero('')
    setImeiManualUltimo('')
    setCantidadManualTira('')
    setImeisManuales('')
    setImeiManualPrimeroValidado(false)
    setImeiManualUltimoValidado(false)
    setImeisManualesConfirmados([])
    setLecturasTiraPedido([])
    setImeisRevisionTiraPedido(null)
  }

  async function cerrarSesionAlmacen() {
    await cerrarVinculoScanner()
    await onLogout()
  }

  async function consultarSaldoRutaDirecto(idRutaConsulta) {
    const consulta = ++consultaSaldoRutaDirectoRef.current
    setCargandoSaldoRutaDirecto(true)
    setErrorSaldoRutaDirecto('')
    try {
      const saldo = await api(`/api/auth/almacen/cuadres/rutas/${idRutaConsulta}/saldo`, {
        headers: { Authorization: `Bearer ${session.token}` },
      })
      if (consulta === consultaSaldoRutaDirectoRef.current) setSaldoRutaDirecto(saldoConNombresVisibles(saldo))
    } catch (err) {
      if (consulta === consultaSaldoRutaDirectoRef.current) setErrorSaldoRutaDirecto(err.message)
    } finally {
      if (consulta === consultaSaldoRutaDirectoRef.current) setCargandoSaldoRutaDirecto(false)
    }
  }

  function cerrarPedidoDirecto() {
    consultaSaldoRutaDirectoRef.current += 1
    setPedidoDirectoAbierto(false)
  }

  function abrirPedidoDirecto() {
    if (!rutaSeleccionada?.idVendedor) {
      setErrorAlmacen('Selecciona una ruta que tenga vendedor asignado.')
      return
    }
    setPedidoDirectoAbierto(true)
    setTirasPedidoDirecto([])
    setObservacionPedidoDirecto('')
    setModoPedidoDirecto('cantidad')
    setPrimerImeiDirecto('')
    setUltimoImeiDirecto('')
    setCantidadTiraDirecta('')
    setImeisIndividualesDirectos('')
    setEfectivoTigoDirecto('')
    setTigoDirectoValidado(null)
    setValidandoTigoDirecto(false)
    setErrorPedidoDirecto('')
    setSaldoRutaDirecto(null)
    setErrorSaldoRutaDirecto('')
    setErrorAlmacen('')
    setMensajeAlmacen('')
    consultarSaldoRutaDirecto(rutaSeleccionada.idRuta)
  }

  function generarImeisPedidoDirecto() {
    if (modoPedidoDirecto === 'individual') {
      const imeis = imeisIndividualesDirectos.split(/[\s,;]+/).map((valor) => valor.trim()).filter(Boolean)
      if (!imeis.length) throw new Error('Ingresa al menos un IMEI.')
      if (imeis.length > 1000) throw new Error('Una tira no puede superar 1000 IMEI.')
      if (imeis.some((imei) => !/^\d{1,18}$/.test(imei))) throw new Error('Cada IMEI debe ser numerico y tener hasta 18 digitos.')
      return imeis
    }
    if (!/^\d{1,18}$/.test(primerImeiDirecto)) throw new Error('Ingresa el primer IMEI numerico.')
    const primero = BigInt(primerImeiDirecto)
    let cantidad
    if (modoPedidoDirecto === 'cantidad') {
      if (!/^\d+$/.test(cantidadTiraDirecta)) throw new Error('Ingresa una cantidad entera.')
      cantidad = Number(cantidadTiraDirecta)
      if (!Number.isSafeInteger(cantidad) || cantidad < 1 || cantidad > 1000) throw new Error('La cantidad debe estar entre 1 y 1000.')
    } else {
      if (!/^\d{1,18}$/.test(ultimoImeiDirecto)) throw new Error('Ingresa el ultimo IMEI numerico.')
      const diferencia = BigInt(ultimoImeiDirecto) - primero + 1n
      if (diferencia < 1n || diferencia > 1000n) throw new Error('El rango debe contener entre 1 y 1000 IMEI consecutivos.')
      cantidad = Number(diferencia)
    }
    return Array.from({ length: cantidad }, (_, indice) => String(primero + BigInt(indice)))
  }

  function navegarCapturaPedidoDirecto(event) {
    if (event.altKey || event.ctrlKey || event.metaKey || !['ArrowDown', 'ArrowUp'].includes(event.key)) return
    const controles = [...event.currentTarget.querySelectorAll('[data-direct-capture]:not(:disabled)')]
    const posicion = controles.indexOf(event.target)
    if (posicion < 0) return
    const siguiente = controles[posicion + (event.key === 'ArrowDown' ? 1 : -1)]
    if (!siguiente) return
    event.preventDefault()
    siguiente.focus()
  }

  async function agregarTiraPedidoDirecto() {
    setErrorPedidoDirecto('')
    setGuardandoPedidoDirecto(true)
    try {
      const imeis = generarImeisPedidoDirecto()
      const nuevos = new Set(imeis)
      if (nuevos.size !== imeis.length) throw new Error('La tira contiene IMEI repetidos.')
      const anteriores = new Set(tirasPedidoDirecto.flatMap((tira) => tira.imeis))
      if (imeis.some((imei) => anteriores.has(imei))) throw new Error('Un IMEI ya esta incluido en otra tira de esta entrega.')
      const resultados = await api('/api/auth/almacen/pedidos-directos/validar-imeis', {
        method: 'POST', headers: { Authorization: `Bearer ${session.token}` }, body: JSON.stringify({ imeis }),
      })
      const invalido = resultados.find((item) => !item.valido)
      if (invalido) throw new Error(`${invalido.imei}: ${invalido.motivo || 'IMEI no disponible.'}`)
      if (resultados.some((item) => anteriores.has(item.imei))) throw new Error('Un IMEI ya esta incluido en otra tira de esta entrega.')
      const productos = [...new Set(resultados.map((item) => item.idProducto))]
      if (productos.length !== 1) throw new Error('Una tira debe contener IMEI de un solo producto. Sepáralos en tiras distintas.')
      setTirasPedidoDirecto((actuales) => [...actuales, {
        numero: actuales.length ? Math.max(...actuales.map((item) => item.numero)) + 1 : 1,
        modo: modoPedidoDirecto, idProducto: productos[0], producto: resultados[0].producto, imeis: resultados.map((item) => item.imei),
      }])
      setPrimerImeiDirecto('')
      setUltimoImeiDirecto('')
      setCantidadTiraDirecta('')
      setImeisIndividualesDirectos('')
    } catch (err) { setErrorPedidoDirecto(err.message) } finally { setGuardandoPedidoDirecto(false) }
  }

  async function guardarPedidoDirecto() {
    if (!rutaSeleccionada?.idVendedor) return
    setErrorPedidoDirecto('')
    setGuardandoPedidoDirecto(true)
    try {
      const conteos = new Map()
      tirasPedidoDirecto.forEach((tira) => conteos.set(tira.idProducto, (conteos.get(tira.idProducto) || 0) + tira.imeis.length))
      const tigo = efectivoTigoDirecto.trim() ? Number(efectivoTigoDirecto) : 0
      if (efectivoTigoDirecto.trim()) {
        if (!Number.isSafeInteger(tigo) || tigo < 1) throw new Error('El monto de Tigo Money debe ser entero y positivo.')
        if (!tigoDirectoValidado?.valido || tigoDirectoValidado.montoPedido !== tigo) throw new Error('Valida el monto actual de Tigo Money antes de confirmar.')
        await api(`/api/auth/almacen/pedidos-directos/validar-tigo-money?cantidad=${tigo}`, {
          headers: { Authorization: `Bearer ${session.token}` },
        })
        conteos.set(31, tigo)
      }
      if (!conteos.size) throw new Error('Agrega al menos una tira o un monto de Tigo Money.')
      const respuesta = await api('/api/auth/almacen/pedidos-directos', {
        method: 'POST', headers: { Authorization: `Bearer ${session.token}` },
        body: JSON.stringify({
          idRuta: rutaSeleccionada.idRuta, observacion: observacionPedidoDirecto.trim(),
          detalles: [...conteos].map(([idProducto, cantidad]) => ({ idProducto, cantidad })),
          productos: tirasPedidoDirecto.flatMap((tira) => tira.imeis.map((imei) => ({
            idProducto: tira.idProducto, imei, numeroTira: tira.numero, modoTira: tira.modo,
          }))),
        }),
      })
      cerrarPedidoDirecto()
      setMensajeAlmacen(`Entrega directa #${respuesta.idPedidoVendedor} creada y asignada a ${rutaSeleccionada.ruta}.`)
      const params = `fechaDesde=${fechaDesde}&fechaHasta=${fechaHasta}`
      const [listaRutas, listaPedidos] = await Promise.all([
        api(`/api/auth/almacen/rutas?${params}`, { headers: { Authorization: `Bearer ${session.token}` } }),
        api(`/api/auth/almacen/pedidos?${params}${idRuta ? `&idRuta=${idRuta}` : ''}&estadoAprobado=1`, { headers: { Authorization: `Bearer ${session.token}` } }),
      ]).catch(() => [null, null])
      if (listaRutas) setRutas(listaRutas)
      if (listaPedidos) setPedidos(listaPedidos)
    } catch (err) { setErrorPedidoDirecto(err.message) } finally { setGuardandoPedidoDirecto(false) }
  }

  async function validarTigoMoneyDirectoActual() {
    setErrorPedidoDirecto('')
    setTigoDirectoValidado(null)
    const cantidad = Number(efectivoTigoDirecto)
    if (!Number.isSafeInteger(cantidad) || cantidad < 1) {
      setErrorPedidoDirecto('Ingresa un monto entero de Tigo Money mayor a cero.')
      return
    }
    setValidandoTigoDirecto(true)
    try {
      const validacion = await api(`/api/auth/almacen/pedidos-directos/validar-tigo-money?cantidad=${cantidad}`, {
        headers: { Authorization: `Bearer ${session.token}` },
      })
      if (!validacion.valido) throw new Error('No hay saldo suficiente de Tigo Money.')
      setTigoDirectoValidado(validacion)
    } catch (err) { setErrorPedidoDirecto(err.message) } finally { setValidandoTigoDirecto(false) }
  }

  async function configurarContextoPedido(detalle, imeisAsignados) {
    if (!vinculoScanner) return
    if (pedidoSeleccionado?.directo) {
      await api(`/api/scanner/vinculaciones/${vinculoScanner.token}/contexto-directo`, {
        method: 'POST', headers: { Authorization: `Bearer ${session.token}` },
        body: JSON.stringify({ idProducto: detalle.idProducto, producto: detalle.producto, cantidadSolicitada: detalle.cantidad, imeisAsignados }),
      })
    } else {
      await api(`/api/scanner/vinculaciones/${vinculoScanner.token}/contexto`, {
        method: 'POST', headers: { Authorization: `Bearer ${session.token}` },
        body: JSON.stringify({ idPedido: pedidoSeleccionado.idPedido, idDetalle: detalle.idDetalle, imeisAsignados }),
      })
    }
  }

  async function validarImeisPedidoActual(imeis) {
    if (pedidoSeleccionado?.directo) {
      return api('/api/scanner/productos/validar-directo', {
        method: 'POST', headers: { Authorization: `Bearer ${session.token}` },
        body: JSON.stringify({ idProducto: detalleEscaneo.idProducto, cantidadSolicitada: detalleEscaneo.cantidad, imeis }),
      })
    }
    return api('/api/scanner/productos/validar-pedido', {
      method: 'POST', headers: { Authorization: `Bearer ${session.token}` },
      body: JSON.stringify({ idPedido: pedidoSeleccionado.idPedido, idDetalle: detalleEscaneo.idDetalle, tokenVinculacion: vinculoScanner?.token || '', imeis }),
    })
  }

  async function activarCapturaDetalle(detalle) {
    if (!vinculoScanner) {
      setScannerPedidoError('Primero vincula el telefono desde el modulo Vincular dispositivo.')
      return
    }
    if (lecturasTiraPedido.length && detalleEscaneo?.idDetalle !== detalle.idDetalle) {
      setScannerPedidoError('Agrega o limpia la tira actual antes de cambiar de producto.')
      return
    }
    const existentes = imeisAsignadosDetalle(detalle.idDetalle)
    try {
      await configurarContextoPedido(detalle, existentes)
      setDetalleEscaneo(detalle)
      setIngresoManualPedido(false)
      setModoTiraPedido('rango')
      setLecturasTiraPedido([])
      setImeisRevisionTiraPedido(null)
      setListaScannerCerrada(false)
      setScannerPedidoError('')
    } catch (err) {
      setScannerPedidoError(err.message)
    }
  }

  async function activarCapturaManual(detalle) {
    if (lecturasTiraPedido.length && detalleEscaneo?.idDetalle !== detalle.idDetalle) {
      setScannerPedidoError('Agrega o limpia la tira actual antes de cambiar de producto.')
      return
    }
    let vinculoActivo = vinculoScanner
    if (!vinculoActivo) {
      vinculoActivo = await crearVinculoScanner()
      if (!vinculoActivo) return
    }
    setDetalleEscaneo(detalle)
    setIngresoManualPedido(true)
    setModoTiraPedido('rango')
    setLecturasTiraPedido([])
    setImeisRevisionTiraPedido(null)
    setImeiManualPrimero('')
    setImeiManualUltimo('')
    setCantidadManualTira('')
    setImeisManuales('')
    setImeiManualPrimeroValidado(false)
    setImeiManualUltimoValidado(false)
    setImeisManualesConfirmados([])
    setListaScannerCerrada(false)
    setScannerPedidoError('')
  }

  async function validarImeiManualEnBase(codigoIngresado) {
    const imei = String(codigoIngresado || '').replace(/[^0-9]/g, '')
    if (!imei) throw new Error('Ingresa un IMEI antes de confirmar.')
    if (imei.length > 18) throw new Error('El IMEI debe tener como maximo 18 digitos.')
    const validacion = await validarImeisPedidoActual([imei])
    if (!validacion.tiraValida) {
      const invalido = validacion.productos?.find((producto) => !producto.valido)
      throw new Error(invalido?.motivo || `El IMEI ${imei} no es valido para este producto.`)
    }
    return imei
  }

  async function confirmarExtremoManual(tipo) {
    if (tipo === 'ultimo' && !imeiManualPrimeroValidado) return
    setValidandoImeiManual(true)
    setScannerPedidoError('')
    try {
      const imei = await validarImeiManualEnBase(tipo === 'primero' ? imeiManualPrimero : imeiManualUltimo)
      if (tipo === 'primero') {
        const todosAsignados = Object.values(asignacionesPedido).flatMap((tiras) => tiras.flatMap((tira) => tira.imeis))
        if (todosAsignados.includes(imei)) throw new Error(`El IMEI ${imei} ya esta incluido en el pedido.`)
        if (imeisAsignadosDetalle(detalleEscaneo.idDetalle).length >= detalleEscaneo.cantidad) throw new Error(`Ya se completo la cantidad solicitada de ${detalleEscaneo.cantidad}.`)
        setImeiManualPrimero(imei)
        setImeiManualPrimeroValidado(true)
        setImeiManualUltimo('')
        setImeiManualUltimoValidado(false)
        setLecturasTiraPedido(modoTiraPedido === 'cantidad' ? [{ id: crypto.randomUUID(), codigo: imei }] : [])
      } else {
        if (BigInt(imei) < BigInt(imeiManualPrimero)) throw new Error('El ultimo IMEI debe ser mayor o igual que el primero.')
        setImeiManualUltimo(imei)
        setImeiManualUltimoValidado(true)
        setLecturasTiraPedido([
          { id: crypto.randomUUID(), codigo: imeiManualPrimero },
          { id: crypto.randomUUID(), codigo: imei },
        ])
        setListaScannerCerrada(true)
      }
      setImeisRevisionTiraPedido(null)
    } catch (err) {
      if (tipo === 'primero') setImeiManualPrimeroValidado(false)
      else setImeiManualUltimoValidado(false)
      setLecturasTiraPedido([])
      setScannerPedidoError(err.message)
    } finally {
      setValidandoImeiManual(false)
    }
  }

  async function confirmarImeiManualIndividual() {
    setValidandoImeiManual(true)
    setScannerPedidoError('')
    try {
      const imei = await validarImeiManualEnBase(imeisManuales)
      const todosAsignados = Object.values(asignacionesPedido).flatMap((tiras) => tiras.flatMap((tira) => tira.imeis))
      if (imeisManualesConfirmados.includes(imei) || todosAsignados.includes(imei)) throw new Error(`El IMEI ${imei} ya esta incluido en el pedido.`)
      if (imeisAsignadosDetalle(detalleEscaneo.idDetalle).length + imeisManualesConfirmados.length + 1 > detalleEscaneo.cantidad) throw new Error(`La tira excede la cantidad solicitada de ${detalleEscaneo.cantidad}.`)
      const confirmados = [...imeisManualesConfirmados, imei]
      setImeisManualesConfirmados(confirmados)
      setLecturasTiraPedido(confirmados.map((codigo) => ({ id: crypto.randomUUID(), codigo })))
      setImeisManuales('')
      setImeisRevisionTiraPedido(null)
      setListaScannerCerrada(true)
    } catch (err) {
      setScannerPedidoError(err.message)
    } finally {
      setValidandoImeiManual(false)
    }
  }

  function quitarImeiManualConfirmado(imei) {
    const confirmados = imeisManualesConfirmados.filter((codigo) => codigo !== imei)
    setImeisManualesConfirmados(confirmados)
    setLecturasTiraPedido(confirmados.map((codigo) => ({ id: crypto.randomUUID(), codigo })))
    setImeisRevisionTiraPedido(null)
  }

  function calcularImeisTiraPedido() {
    const escaneados = lecturasTiraPedido.map((item) => String(item.codigo).replace(/[^0-9]/g, ''))
    if (modoTiraPedido === 'individual') return escaneados
    if (modoTiraPedido === 'cantidad') {
      if (escaneados.length !== 1) throw new Error('Confirma exactamente el primer IMEI de la tira.')
      if (!/^\d+$/.test(cantidadManualTira)) throw new Error('Ingresa una cantidad entera mayor que cero.')
      const cantidad = Number(cantidadManualTira)
      if (!Number.isSafeInteger(cantidad) || cantidad < 1) throw new Error('La cantidad debe ser un numero entero mayor que cero.')
      if (cantidad > 1000) throw new Error('Una tira no puede superar 1000 productos.')
      const primero = BigInt(escaneados[0])
      return Array.from({ length: cantidad }, (_, index) => String(primero + BigInt(index)))
    }
    if (escaneados.length !== 2) throw new Error('Para una tira calculada escanea exactamente el primer y el ultimo IMEI.')
    const primero = BigInt(escaneados[0])
    const ultimo = BigInt(escaneados[1])
    if (ultimo < primero) throw new Error('El ultimo IMEI debe ser mayor o igual que el primero.')
    const cantidad = ultimo - primero + 1n
    if (cantidad > 1000n) throw new Error('Una tira no puede superar 1000 productos.')
    return Array.from({ length: Number(cantidad) }, (_, index) => String(primero + BigInt(index)))
  }

  async function limpiarTiraPedido(nuevoModo = modoTiraPedido) {
    setModoTiraPedido(nuevoModo)
    setLecturasTiraPedido([])
    setImeisRevisionTiraPedido(null)
    setListaScannerCerrada(false)
    setImeiManualPrimero('')
    setImeiManualUltimo('')
    setCantidadManualTira('')
    setImeisManuales('')
    setImeiManualPrimeroValidado(false)
    setImeiManualUltimoValidado(false)
    setImeisManualesConfirmados([])
    if (!detalleEscaneo || !pedidoSeleccionado || !vinculoScanner) return
    await api(`/api/scanner/publico/${vinculoScanner.token}/reanudar-lista`, { method: 'POST' }).catch(() => null)
    await configurarContextoPedido(detalleEscaneo, imeisAsignadosDetalle(detalleEscaneo.idDetalle)).catch((err) => setScannerPedidoError(err.message))
  }

  function mostrarInformacionTiraPedido() {
    setScannerPedidoError('')
    try {
      const imeis = calcularImeisTiraPedido()
      if (!imeis.length) throw new Error('Escanea al menos un IMEI para revisar la tira.')
      setImeisRevisionTiraPedido(imeis)
    } catch (err) {
      setImeisRevisionTiraPedido(null)
      setScannerPedidoError(err.message)
    }
  }

  function eliminarImeiRevisionTiraPedido(imei) {
    setImeisRevisionTiraPedido((actuales) => actuales?.filter((actual) => actual !== imei) || null)
  }

  async function agregarTiraPedido() {
    if (!detalleEscaneo || !pedidoSeleccionado) return
    setValidandoTiraPedido(true)
    setScannerPedidoError('')
    try {
      const imeis = imeisRevisionTiraPedido ?? calcularImeisTiraPedido()
      if (!imeis.length) throw new Error('Escanea al menos un IMEI.')
      if (new Set(imeis).size !== imeis.length) throw new Error('La tira contiene IMEI repetidos.')
      const todosAsignados = Object.values(asignacionesPedido).flatMap((tiras) => tiras.flatMap((tira) => tira.imeis))
      const repetido = imeis.find((imei) => todosAsignados.includes(imei))
      if (repetido) throw new Error(`El IMEI ${repetido} ya esta incluido en el pedido.`)
      const existentes = imeisAsignadosDetalle(detalleEscaneo.idDetalle)
      if (existentes.length + imeis.length > detalleEscaneo.cantidad) throw new Error(`La tira excede la cantidad solicitada de ${detalleEscaneo.cantidad}.`)
      const validacion = await validarImeisPedidoActual(imeis)
      if (!validacion.tiraValida) {
        const errores = validacion.productos.filter((item) => !item.valido).map((item) => `${item.imei}: ${item.motivo}`).join(' | ')
        throw new Error(errores)
      }
      const tira = { id: crypto.randomUUID(), numero: (asignacionesPedido[detalleEscaneo.idDetalle]?.length || 0) + 1, modo: modoTiraPedido, imeis }
      const nuevasTiras = [...(asignacionesPedido[detalleEscaneo.idDetalle] || []), tira]
      const nuevosImeis = nuevasTiras.flatMap((item) => item.imeis)
      setAsignacionesPedido((actual) => ({ ...actual, [detalleEscaneo.idDetalle]: nuevasTiras }))
      setLecturasTiraPedido([])
      setImeisRevisionTiraPedido(null)
      setImeiManualPrimero('')
      setImeiManualUltimo('')
      setCantidadManualTira('')
      setImeisManuales('')
      setImeiManualPrimeroValidado(false)
      setImeiManualUltimoValidado(false)
      setImeisManualesConfirmados([])
      if (vinculoScanner) {
        await api(`/api/scanner/publico/${vinculoScanner.token}/reanudar-lista`, { method: 'POST' })
        await configurarContextoPedido(detalleEscaneo, nuevosImeis)
      }
      setListaScannerCerrada(false)
    } catch (err) {
      setScannerPedidoError(err.message)
    } finally {
      setValidandoTiraPedido(false)
    }
  }

  async function quitarTiraPedido(idDetalle, idTira) {
    const nuevas = (asignacionesPedido[idDetalle] || []).filter((tira) => tira.id !== idTira).map((tira, index) => ({ ...tira, numero: index + 1 }))
    setAsignacionesPedido((actual) => ({ ...actual, [idDetalle]: nuevas }))
    if (detalleEscaneo?.idDetalle === idDetalle && vinculoScanner) {
      await configurarContextoPedido(detalleEscaneo, nuevas.flatMap((tira) => tira.imeis)).catch((err) => setScannerPedidoError(err.message))
    }
  }

  useEffect(() => {
    let active = true
    const params = `fechaDesde=${fechaDesde}&fechaHasta=${fechaHasta}`
    const estadoParam = modoPedidos === 'pendientes' ? '&estadoAprobado=1' : modoPedidos === 'confirmados' ? '&estadoAprobado=2' : ''
    queueMicrotask(() => {
      if (!active) return
      setCargandoRutas(true)
      setCargandoPedidos(true)
      setErrorAlmacen('')
      Promise.all([
        api(`/api/auth/almacen/rutas?${params}`, { headers: { Authorization: `Bearer ${session.token}` } }),
        api(`/api/auth/almacen/pedidos?${params}${idRuta ? `&idRuta=${idRuta}` : ''}${estadoParam}`, { headers: { Authorization: `Bearer ${session.token}` } }),
      ])
        .then(([listaRutas, listaPedidos]) => { if (active) { setRutas(listaRutas); setPedidos(listaPedidos) } })
        .catch((err) => { if (active) setErrorAlmacen(err.message) })
        .finally(() => { if (active) { setCargandoRutas(false); setCargandoPedidos(false) } })
    })
    return () => { active = false }
  }, [session.token, fechaDesde, fechaHasta, idRuta, modoPedidos])

  useEffect(() => {
    const controller = new AbortController()
    let active = true
    let reconnectTimer

    const conectar = async () => {
      try {
        await escucharEventosPedidos(session.token, controller.signal, (evento) => {
          if (!active) return
          setNotificacionPedido(evento)
          setRutaNueva(evento.idRuta)
          const fechaEvento = evento.fechaRegistro?.slice(0, 10) ?? hoy
          if (fechaEvento < fechaDesde || fechaEvento > fechaHasta) return
          setRutas((actuales) => {
            const index = actuales.findIndex((ruta) => ruta.idRuta === evento.idRuta)
            if (index < 0) return actuales
            const rutaActualizada = {
              ...actuales[index],
              pedidosPendientes: actuales[index].pedidosPendientes + 1,
            }
            return [rutaActualizada, ...actuales.filter((_, itemIndex) => itemIndex !== index)]
          })
        })
        if (active) reconnectTimer = setTimeout(conectar, 2500)
      } catch (error) {
        if (active && error.name !== 'AbortError') reconnectTimer = setTimeout(conectar, 2500)
      }
    }

    conectar()
    return () => {
      active = false
      controller.abort()
      clearTimeout(reconnectTimer)
    }
  }, [session.token, fechaDesde, fechaHasta, hoy])

  useEffect(() => {
    if (!notificacionPedido) return undefined
    const timer = setTimeout(() => {
      setNotificacionPedido(null)
      setRutaNueva(null)
    }, 6500)
    return () => clearTimeout(timer)
  }, [notificacionPedido])

  function seleccionarRuta(ruta) {
    setIdRuta(String(ruta.idRuta))
    setModoPedidos('pendientes')
    setBuscarPedidoId('')
  }

  async function verDetalle(pedido, vista = 'pedido') {
    setPedidoSeleccionado(pedido)
    setVistaDetalle(vista)
    setFechaEntrega(hoy)
    setDetallePedido([])
    setProductosAsignados([])
    setDetalleEscaneo(null)
    setIngresoManualPedido(false)
    setImeiManualPrimero('')
    setImeiManualUltimo('')
    setCantidadManualTira('')
    setImeisManuales('')
    setImeiManualPrimeroValidado(false)
    setImeiManualUltimoValidado(false)
    setImeisManualesConfirmados([])
    setModoTiraPedido('rango')
    setLecturasTiraPedido([])
    setAsignacionesPedido({})
    setTigoMoneyValidado({})
    setValidandoTigoMoney(null)
    setEditandoPedidoAlmacen(false)
    setCantidadesPedidoAlmacen({})
    setComentarioPedidoAlmacen(pedido.comentarioAlmacen || '')
    setGuardandoPedidoAlmacen(false)
    setPromedioPedidoAlmacenVisible(false)
    setPromediosPedidoAlmacen([])
    setCargandoPromedioPedidoAlmacen(false)
    setPromedioPedidoAlmacenError('')
    setSaldoPedidoAlmacenVisible(false)
    setSaldoPedidoAlmacen(null)
    setCargandoSaldoPedidoAlmacen(false)
    setSaldoPedidoAlmacenError('')
    setScannerPedidoError('')
    setCargandoDetalle(true)
    setErrorAlmacen('')
    try {
      const headers = { Authorization: `Bearer ${session.token}` }
      if (pedido.estadoAprobado === 2) {
        const [detalle, asignados] = await Promise.all([
          api(`/api/auth/almacen/pedidos/${pedido.idPedido}/detalle`, { headers }),
          api(`/api/auth/almacen/pedidos/${pedido.idPedido}/productos-asignados`, { headers }),
        ])
        setDetallePedido(detalle)
        setProductosAsignados(asignados)
      } else {
        const detalle = await api(`/api/auth/almacen/pedidos/${pedido.idPedido}/detalle`, { headers })
        setDetallePedido(detalle)
        setCantidadesPedidoAlmacen(Object.fromEntries(detalle.map((item) => [item.idDetalle, item.cantidad])))
      }
    } catch (err) {
      setErrorAlmacen(err.message)
      setPedidoSeleccionado(null)
    } finally {
      setCargandoDetalle(false)
    }
  }

  async function cerrarDetalleAlmacen() {
    const pedido = pedidoSeleccionado
    setPedidoSeleccionado(null)
    setDetallePedido([])
    setProductosAsignados([])
    setDetalleEscaneo(null)
    setIngresoManualPedido(false)
    setImeiManualPrimero('')
    setImeiManualUltimo('')
    setCantidadManualTira('')
    setImeisManuales('')
    setImeiManualPrimeroValidado(false)
    setImeiManualUltimoValidado(false)
    setImeisManualesConfirmados([])
    setLecturasTiraPedido([])
    setAsignacionesPedido({})
    setTigoMoneyValidado({})
    setValidandoTigoMoney(null)
    setEditandoPedidoAlmacen(false)
    setCantidadesPedidoAlmacen({})
    setComentarioPedidoAlmacen('')
    setGuardandoPedidoAlmacen(false)
    setPromedioPedidoAlmacenVisible(false)
    setPromediosPedidoAlmacen([])
    setCargandoPromedioPedidoAlmacen(false)
    setPromedioPedidoAlmacenError('')
    setSaldoPedidoAlmacenVisible(false)
    setSaldoPedidoAlmacen(null)
    setCargandoSaldoPedidoAlmacen(false)
    setSaldoPedidoAlmacenError('')
    setScannerPedidoError('')
    if (pedido?.estadoAprobado === 1 && !pedido?.directo && vinculoScanner) {
      await api(`/api/scanner/vinculaciones/${vinculoScanner.token}/pedidos/${pedido.idPedido}/reservas`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${session.token}` },
      }).catch(() => null)
    }
  }

  async function mostrarPromedioPedidoAlmacen() {
    if (promedioPedidoAlmacenVisible) {
      setPromedioPedidoAlmacenVisible(false)
      return
    }
    if (!pedidoSeleccionado) return
    setPromedioPedidoAlmacenVisible(true)
    setPromedioPedidoAlmacenError('')
    if (promediosPedidoAlmacen.length) return
    setCargandoPromedioPedidoAlmacen(true)
    try {
      const data = await api(`/api/auth/almacen/pedidos/${pedidoSeleccionado.idPedido}/promedio-venta`, {
        headers: { Authorization: `Bearer ${session.token}` },
      })
      setPromediosPedidoAlmacen(data)
    } catch (err) {
      setPromedioPedidoAlmacenError(err.message)
    } finally {
      setCargandoPromedioPedidoAlmacen(false)
    }
  }

  async function mostrarSaldoPedidoAlmacen() {
    if (saldoPedidoAlmacenVisible) {
      setSaldoPedidoAlmacenVisible(false)
      return
    }
    if (!pedidoSeleccionado) return
    setSaldoPedidoAlmacenVisible(true)
    setSaldoPedidoAlmacenError('')
    if (saldoPedidoAlmacen) return
    setCargandoSaldoPedidoAlmacen(true)
    try {
      const data = await api(`/api/auth/almacen/pedidos/${pedidoSeleccionado.idPedido}/saldo-ruta`, {
        headers: { Authorization: `Bearer ${session.token}` },
      })
      setSaldoPedidoAlmacen(saldoConNombresVisibles(data))
    } catch (err) {
      setSaldoPedidoAlmacenError(err.message)
    } finally {
      setCargandoSaldoPedidoAlmacen(false)
    }
  }

  async function validarTigoMoneyPedido(detalle) {
    if (!pedidoSeleccionado) return
    setValidandoTigoMoney(detalle.idDetalle)
    setScannerPedidoError('')
    try {
      const endpoint = pedidoSeleccionado.directo
        ? `/api/auth/almacen/pedidos-directos/validar-tigo-money?cantidad=${detalle.cantidad}`
        : `/api/auth/almacen/pedidos/${pedidoSeleccionado.idPedido}/validar-tigo-money`
      const validacion = await api(endpoint, {
        headers: { Authorization: `Bearer ${session.token}` },
      })
      setTigoMoneyValidado((actual) => ({ ...actual, [detalle.idDetalle]: validacion }))
    } catch (err) {
      setTigoMoneyValidado((actual) => {
        const siguiente = { ...actual }
        delete siguiente[detalle.idDetalle]
        return siguiente
      })
      setScannerPedidoError(err.message)
    } finally {
      setValidandoTigoMoney(null)
    }
  }

  function iniciarModificacionPedidoAlmacen() {
    setCantidadesPedidoAlmacen(Object.fromEntries(detallePedido.map((item) => [item.idDetalle, item.cantidad])))
    setComentarioPedidoAlmacen(pedidoSeleccionado?.comentarioAlmacen || '')
    setScannerPedidoError('')
    setEditandoPedidoAlmacen(true)
  }

  function cancelarModificacionPedidoAlmacen() {
    setCantidadesPedidoAlmacen(Object.fromEntries(detallePedido.map((item) => [item.idDetalle, item.cantidad])))
    setComentarioPedidoAlmacen(pedidoSeleccionado?.comentarioAlmacen || '')
    setScannerPedidoError('')
    setEditandoPedidoAlmacen(false)
  }

  async function guardarModificacionPedidoAlmacen() {
    if (!pedidoSeleccionado) return
    const detalles = detallePedido.map((item) => ({
      idDetalle: item.idDetalle,
      cantidad: Number(cantidadesPedidoAlmacen[item.idDetalle]),
      cantidadOriginal: item.cantidad,
    }))
    if (detalles.some((item) => !Number.isInteger(item.cantidad) || item.cantidad < 0)) {
      setScannerPedidoError('Todas las cantidades deben ser números enteros iguales o mayores a cero.')
      return
    }
    if (!detalles.some((item) => item.cantidad > 0)) {
      setScannerPedidoError('El pedido debe conservar al menos un producto.')
      return
    }
    if (detalles.some((item) => item.cantidad > item.cantidadOriginal)) {
      setScannerPedidoError('Almacén solo puede disminuir las cantidades del pedido.')
      return
    }
    if (!detalles.some((item) => item.cantidad < item.cantidadOriginal)) {
      setScannerPedidoError('Disminuye al menos una cantidad antes de guardar.')
      return
    }
    if (!comentarioPedidoAlmacen.trim()) {
      setScannerPedidoError('Escribe el motivo por el que almacén modifica el pedido.')
      return
    }
    setGuardandoPedidoAlmacen(true)
    setScannerPedidoError('')
    try {
      const actualizado = await api(`/api/auth/almacen/pedidos/${pedidoSeleccionado.idPedido}`, {
        method: 'PUT',
        headers: { Authorization: `Bearer ${session.token}` },
        body: JSON.stringify({
          detalles: detalles.map(({ idDetalle, cantidad }) => ({ idDetalle, cantidad })),
          comentarioAlmacen: comentarioPedidoAlmacen.trim(),
        }),
      })
      const detalleActualizado = await api(`/api/auth/almacen/pedidos/${pedidoSeleccionado.idPedido}/detalle`, {
        headers: { Authorization: `Bearer ${session.token}` },
      })
      const pedidoActualizado = {
        ...pedidoSeleccionado,
        total: actualizado.total,
        cantidadProductos: actualizado.cantidadProductos,
        cantidadUnidades: actualizado.cantidadUnidades,
        modificadoPorAlmacen: actualizado.modificadoPorAlmacen,
        comentarioAlmacen: actualizado.comentarioAlmacen,
      }
      setPedidoSeleccionado(pedidoActualizado)
      setPedidos((actuales) => actuales.map((item) => item.idPedido === pedidoActualizado.idPedido ? { ...item, ...pedidoActualizado } : item))
      setDetallePedido(detalleActualizado)
      setCantidadesPedidoAlmacen(Object.fromEntries(detalleActualizado.map((item) => [item.idDetalle, item.cantidad])))
      setAsignacionesPedido({})
      setTigoMoneyValidado({})
      setDetalleEscaneo(null)
      setLecturasTiraPedido([])
      setEditandoPedidoAlmacen(false)
    } catch (err) {
      setScannerPedidoError(err.message)
    } finally {
      setGuardandoPedidoAlmacen(false)
    }
  }

  async function aprobarPedido() {
    if (!pedidoSeleccionado) return
    setCargandoDetalle(true)
    setErrorAlmacen('')
    try {
      const esDirecto = Boolean(pedidoSeleccionado.directo)
      const productos = detallePedido.flatMap((detalle) => (asignacionesPedido[detalle.idDetalle] || []).flatMap((tira) => tira.imeis.map((imei) => ({
        ...(esDirecto ? { idProducto: detalle.idProducto } : { idDetalle: detalle.idDetalle }), imei, numeroTira: tira.numero, modoTira: tira.modo,
      }))))
      const respuesta = await api(esDirecto ? '/api/auth/almacen/pedidos-directos' : `/api/auth/almacen/pedidos/${pedidoSeleccionado.idPedido}/aprobar`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${session.token}` },
        body: JSON.stringify(esDirecto ? {
          idRuta: pedidoSeleccionado.idRuta, observacion: pedidoSeleccionado.observacion || '',
          detalles: detallePedido.map((detalle) => ({ idProducto: detalle.idProducto, cantidad: detalle.cantidad })), productos,
        } : { fechaEntrega, tokenVinculacion: vinculoScanner?.token, productos }),
      })
      setPedidoSeleccionado(null)
      setDetallePedido([])
      setModoPedidos('pendientes')
      const params = `fechaDesde=${fechaDesde}&fechaHasta=${fechaHasta}`
      const [listaRutas, listaPedidos] = await Promise.all([
        api(`/api/auth/almacen/rutas?${params}`, { headers: { Authorization: `Bearer ${session.token}` } }),
        api(`/api/auth/almacen/pedidos?${params}${idRuta ? `&idRuta=${idRuta}` : ''}&estadoAprobado=1`, { headers: { Authorization: `Bearer ${session.token}` } }),
      ])
      setRutas(listaRutas)
      setPedidos(listaPedidos)
      if (esDirecto) setMensajeAlmacen(`Entrega directa #${respuesta.idPedidoVendedor} creada y asignada correctamente a ${pedidoSeleccionado.ruta}.`)
    } catch (err) {
      setErrorAlmacen(err.message)
    } finally {
      setCargandoDetalle(false)
    }
  }

  return (
    <main className="warehouse-page">
      <header className="topbar">
        <div className="topbar-brand" data-tour="warehouse-brand"><BrandMark /><span>Operaciones de Almacén</span></div>
        <div className="topbar-user">
          <div className="avatar">{initials}</div>
          <div><strong>{usuario.nombre}</strong><span>{usuario.sucursal.nombre}</span></div>
          <button type="button" onClick={cerrarSesionAlmacen}>Cerrar sesión</button>
        </div>
      </header>

      {notificacionPedido && (
        <button className="new-order-toast" type="button" onClick={() => { setIdRuta(String(notificacionPedido.idRuta)); setModoPedidos('pendientes'); setBuscarPedidoId(''); setNotificacionPedido(null) }}>
          <span>Nuevo pedido</span>
          <strong>#{notificacionPedido.idPedido} · {notificacionPedido.ruta}</strong>
          <small>{notificacionPedido.tecnico}</small>
        </button>
      )}

      <section
        className={`warehouse-workbench warehouse-workbench--resizable ${anchosPaneles.menuOculto ? 'warehouse-workbench--menu-hidden' : ''} ${moduloAlmacen !== 'pedidos' ? 'warehouse-workbench--single' : ''}`}
        style={{ '--warehouse-menu-width': `${anchosPaneles.menu}px`, '--warehouse-routes-width': `${anchosPaneles.rutas}px` }}
      >
        <button
          className="warehouse-sidebar-toggle"
          type="button"
          aria-label={anchosPaneles.menuOculto ? 'Mostrar menú de almacén' : 'Ocultar menú de almacén'}
          title={anchosPaneles.menuOculto ? 'Mostrar menú' : 'Ocultar menú'}
          onClick={() => setAnchosPaneles((actual) => ({ ...actual, menuOculto: !actual.menuOculto }))}
        >{anchosPaneles.menuOculto ? '›' : '‹'}</button>
        <nav className="warehouse-module-sidebar" aria-label="M&oacute;dulos de almac&eacute;n">
          <div className="warehouse-module-heading"><span>MEN&Uacute;</span><strong>Almac&eacute;n</strong></div>
          <button data-tour="warehouse-orders" className={moduloAlmacen === 'pedidos' ? 'active' : ''} type="button" onClick={() => setModuloAlmacen('pedidos')}>
            <span className="warehouse-module-icon">P</span>
            <div><strong>Pedidos pendientes</strong><small>Revisar y aprobar</small></div>
            {rutas.reduce((total, item) => total + item.pedidosPendientes, 0) > 0 && <b>{rutas.reduce((total, item) => total + item.pedidosPendientes, 0)}</b>}
          </button>
          <button data-tour="warehouse-cashups" className={moduloAlmacen === 'cuadres' ? 'active warehouse-module-cuadre' : 'warehouse-module-cuadre'} type="button" onClick={() => setModuloAlmacen('cuadres')}>
            <span className="warehouse-module-icon">C</span>
            <div><strong>Ver cuadres</strong><small>{cuadresPendientesHoy > 0 ? 'Pendientes de aprobación' : 'Control diario por ruta'}</small></div>
            {cuadresPendientesHoy > 0 ? <b>{cuadresPendientesHoy}</b> : cuadresRealizadosHoy > 0 && <b>{cuadresRealizadosHoy}</b>}
          </button>
          <button className={moduloAlmacen === 'cierre' ? 'active' : ''} type="button" onClick={() => setModuloAlmacen('cierre')}>
            <span className="warehouse-module-icon">A</span>
            <div><strong>Cierre de almacén</strong><small>Saldos y movimientos</small></div>
          </button>
          <button data-tour="warehouse-devices" className={moduloAlmacen === 'dispositivos' ? 'active' : ''} type="button" onClick={() => setModuloAlmacen('dispositivos')}>
            <span className="warehouse-module-icon">D</span>
            <div><strong>Vincular dispositivo</strong><small>Seriales y equipos</small></div>
          </button>
          <button data-tour="warehouse-statistics" className={moduloAlmacen === 'estadisticas' ? 'active' : ''} type="button" onClick={() => setModuloAlmacen('estadisticas')}>
            <span className="warehouse-module-icon">E</span>
            <div><strong>Estadísticas</strong><small>Pedidos y rutas</small></div>
          </button>
          <button className="warehouse-tutorial-button" type="button" onClick={() => setTutorialAbierto(true)}>
            <span className="warehouse-module-icon">?</span>
            <div><strong>Ver tutorial</strong><small>Guía paso a paso</small></div>
          </button>
          <div className="warehouse-module-status"><span /><div><strong>Sistema conectado</strong><small>{usuario.sucursal.nombre}</small></div></div>
        </nav>

        <div className="warehouse-panel-resizer warehouse-panel-resizer--menu" role="separator" aria-label="Cambiar ancho del menú" aria-orientation="vertical" title="Arrastra para cambiar el ancho del menú" onPointerDown={(event) => iniciarRedimensionPanel('menu', event)}><span /></div>

        {moduloAlmacen === 'pedidos' ? <>
        <aside className="seller-sidebar">
          <div className="seller-sidebar-heading"><p>RUTAS</p><span>{rutas.length}</span></div>
          <div className="seller-search"><span>⌕</span><input type="search" placeholder="Buscar ruta o técnico…" value={busqueda} onChange={(event) => setBusqueda(event.target.value)} /></div>
          <button className={`seller-all ${!idRuta ? 'active' : ''}`} type="button" onClick={() => { setIdRuta(''); setModoPedidos('pendientes'); setBuscarPedidoId('') }}><span>Todas las rutas</span><b>{rutas.reduce((total, item) => total + item.pedidosPendientes, 0)}</b></button>
          <div className="seller-list">
            {cargandoRutas ? <div className="seller-loading">Consultando…</div> : rutasFiltradas.map((ruta) => (
              <button className={`${Number(idRuta) === ruta.idRuta ? 'active' : ''} ${rutaNueva === ruta.idRuta ? 'has-new-order' : ''}`} type="button" key={ruta.idRuta} onClick={() => seleccionarRuta(ruta)}>
                <div><strong>{ruta.ruta}</strong><small><b>{ruta.tecnico}</b>{ruta.idVendedor ? ` · Vendedor #${ruta.idVendedor}` : ''}</small></div>
                {ruta.pedidosPendientes > 0 && <b>{ruta.pedidosPendientes}</b>}
              </button>
            ))}
          </div>
        </aside>

        <div className="warehouse-panel-resizer warehouse-panel-resizer--routes" role="separator" aria-label="Cambiar ancho de rutas" aria-orientation="vertical" title="Arrastra para cambiar el ancho de rutas" onPointerDown={(event) => iniciarRedimensionPanel('rutas', event)}><span /></div>

        <section className="warehouse-orders warehouse-orders--workbench">
          <div className="warehouse-orders-heading">
            <div><p>CONTROL DE SOLICITUDES</p><h2>{rutaSeleccionada ? rutaSeleccionada.ruta : 'Todos los pedidos pendientes'}</h2>{rutaSeleccionada && <small>Técnico asignado: {rutaSeleccionada.tecnico}</small>}</div>
            <div className="warehouse-direct-heading-actions">
              {rutaSeleccionada && <button type="button" onClick={abrirPedidoDirecto} disabled={!rutaSeleccionada.idVendedor}>+ Entrega directa</button>}
              <span>{pedidosFiltrados.length} pedido(s)</span>
            </div>
          </div>
          <div className="warehouse-order-toolbar">
            <div className="warehouse-order-tabs">
              <button className={modoPedidos === 'pendientes' ? 'active' : ''} type="button" onClick={() => setModoPedidos('pendientes')}>Pendientes <b>{totalPendientes}</b></button>
              <button className={modoPedidos === 'todos' ? 'active' : ''} type="button" onClick={() => setModoPedidos('todos')}>Todos</button>
              <button className={modoPedidos === 'confirmados' ? 'active' : ''} type="button" onClick={() => setModoPedidos('confirmados')}>Confirmados</button>
            </div>
            <div className="order-id-search"><span>#</span><input type="search" inputMode="numeric" placeholder="Buscar ID de pedido" value={buscarPedidoId} onChange={(event) => setBuscarPedidoId(event.target.value)} /></div>
          </div>
          <div className="warehouse-date-range">
            <label>Desde<input type="date" value={fechaDesde} max={fechaHasta} onChange={(event) => setFechaDesde(event.target.value)} /></label>
            <label>Hasta<input type="date" value={fechaHasta} min={fechaDesde} onChange={(event) => setFechaHasta(event.target.value)} /></label>
            <div className="date-quick-actions">
              <button className={fechaDesde === inicioHistorico && fechaHasta === hoy ? 'active' : ''} type="button" onClick={() => { setFechaDesde(inicioHistorico); setFechaHasta(hoy) }}>Histórico</button>
              <button className={fechaDesde === inicioMes && fechaHasta === hoy ? 'active' : ''} type="button" onClick={() => { setFechaDesde(inicioMes); setFechaHasta(hoy) }}>Este mes</button>
              <button className={fechaDesde === hoy && fechaHasta === hoy ? 'active' : ''} type="button" onClick={() => { setFechaDesde(hoy); setFechaHasta(hoy) }}>Hoy</button>
            </div>
            <div><small>Periodo consultado</small><strong>{fechaDesde === fechaHasta ? fechaDesde : `${fechaDesde} — ${fechaHasta}`}</strong></div>
          </div>

          {errorAlmacen && <div className="warehouse-orders-message warehouse-orders-message--error">{errorAlmacen}</div>}
          {mensajeAlmacen && <div className="warehouse-orders-message warehouse-orders-message--success">{mensajeAlmacen}</div>}
          {cargandoPedidos ? <div className="warehouse-orders-message">Consultando pedidos…</div> : pedidosFiltrados.length === 0 ? <div className="warehouse-orders-message">No existen pedidos con estos filtros.</div> : (
            <div className="warehouse-pending-list">
              {pedidosFiltrados.map((pedido) => (
                <article className="warehouse-pending-order" key={pedido.idPedido}>
                  <div className="warehouse-order-id"><span>Pedido</span><strong>#{pedido.idPedido}</strong></div>
                  <div className="warehouse-order-date"><small>{pedido.tecnico}</small><strong>{dateTime.format(new Date(pedido.fechaRegistro))}</strong><span>{pedido.ruta}</span></div>
                  <dl><div><dt>Productos</dt><dd>{pedido.cantidadProductos}</dd></div><div><dt>Unidades</dt><dd>{pedido.cantidadUnidades}</dd></div><div><dt>Total</dt><dd>{money.format(pedido.total)}</dd></div></dl>
                  <span className={`order-status order-status--${pedido.estadoAprobado === 2 ? 'approved' : 'pending'}`}>{pedido.estadoAprobado === 2 ? 'Aprobado' : 'Pendiente'}</span>
                  <div className="warehouse-order-actions">
                    <button type="button" onClick={() => verDetalle(pedido, 'pedido')}>{pedido.estadoAprobado === 2 ? 'Detalle pedido' : 'Ver detalle'}</button>
                    {pedido.estadoAprobado === 2 && <button type="button" onClick={() => verDetalle(pedido, 'asignados')}>Productos asignados</button>}
                  </div>
                </article>
              ))}
            </div>
          )}
        </section>
        </> : moduloAlmacen === 'cuadres'
          ? <WarehouseCuadresPanel session={session} onResumenHoy={setCuadresRealizadosHoy} onPendientesHoy={setCuadresPendientesHoy} />
          : moduloAlmacen === 'cierre'
          ? <WarehouseClosingPanel session={session} />
          : moduloAlmacen === 'dispositivos'
          ? <WarehouseDevicePanel vinculo={vinculoScanner} qr={qrVinculoScanner} creando={creandoVinculo} error={scannerPedidoError} segundos={segundosScanner} onCrear={crearVinculoScanner} onCerrar={cerrarVinculoScanner} />
          : <WarehouseStatisticsPanel session={session} />}
      </section>

      {pedidoDirectoAbierto && (
        <div className="order-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !guardandoPedidoDirecto && !validandoTigoDirecto) cerrarPedidoDirecto() }}>
          <div className="direct-order-layout" role="dialog" aria-modal="true" aria-labelledby="direct-order-title">
          <section className="order-dialog direct-order-dialog">
            <div className="order-dialog-head"><div><p>ENTREGA INMEDIATA</p><h2 id="direct-order-title">Crear pedido directo</h2><span>{rutaSeleccionada?.ruta} · {rutaSeleccionada?.tecnico}</span></div><button type="button" onClick={cerrarPedidoDirecto} disabled={guardandoPedidoDirecto || validandoTigoDirecto}>×</button></div>
            <div className="direct-order-content">
              <div className="direct-order-notice"><b>Entrega directa</b><span>Agrega las tiras e IMEI reales. El sistema identifica cada producto y cuenta las unidades. El pedido definitivo se crea al confirmar.</span></div>
              <div className="direct-order-mode" role="group" aria-label="Modo de captura">
                {['individual', 'rango', 'cantidad'].map((modo) => <button key={modo} type="button" className={modoPedidoDirecto === modo ? 'active' : ''} onClick={() => { setModoPedidoDirecto(modo); setErrorPedidoDirecto('') }}>{modo === 'individual' ? 'Uno por uno' : modo === 'rango' ? 'Primer y último' : 'Por cantidad'}</button>)}
              </div>
              <div className="direct-order-builder" onKeyDown={navegarCapturaPedidoDirecto}>
                {modoPedidoDirecto === 'individual' ? <label className="direct-order-wide">IMEI (uno por línea o separados por coma)<textarea data-direct-capture rows="3" value={imeisIndividualesDirectos} onChange={(event) => setImeisIndividualesDirectos(event.target.value)} placeholder="IMEI" /></label> : <>
                  <label>Primer IMEI<input data-direct-capture inputMode="numeric" value={primerImeiDirecto} onChange={(event) => setPrimerImeiDirecto(event.target.value)} placeholder="Primer IMEI" /></label>
                  {modoPedidoDirecto === 'rango' ? <label>Último IMEI<input data-direct-capture inputMode="numeric" value={ultimoImeiDirecto} onChange={(event) => setUltimoImeiDirecto(event.target.value)} placeholder="Último IMEI" /></label> : <label>Cantidad de la tira<input data-direct-capture type="number" inputMode="numeric" min="1" max="1000" value={cantidadTiraDirecta} onChange={(event) => setCantidadTiraDirecta(event.target.value)} placeholder="Cantidad" /></label>}
                </>}
                <button data-direct-capture type="button" onClick={agregarTiraPedidoDirecto} disabled={guardandoPedidoDirecto}>{guardandoPedidoDirecto ? 'Validando…' : 'Validar y agregar tira'}</button>
              </div>
              <small className="direct-order-keyboard-hint">Usa ↓ para avanzar hasta Validar y ↑ para volver al campo anterior.</small>
              {errorPedidoDirecto && <div className="direct-order-error" role="alert">{errorPedidoDirecto}</div>}
              <div className="direct-order-lines">
                <header><strong>Tiras listas para entregar</strong><span>{tirasPedidoDirecto.reduce((total, item) => total + item.imeis.length, 0)} unidad(es)</span></header>
                {tirasPedidoDirecto.length ? tirasPedidoDirecto.map((tira) => <article key={tira.numero}><div><strong>{tira.producto}</strong><small>Tira {tira.numero} · {tira.imeis[0]}{tira.imeis.length > 1 ? ` – ${tira.imeis[tira.imeis.length - 1]}` : ''}</small><details className="direct-order-imeis"><summary>Ver {tira.imeis.length} IMEI</summary><div>{tira.imeis.join(' · ')}</div></details></div><b>{tira.imeis.length}</b><span>{tira.modo}</span><button type="button" onClick={() => setTirasPedidoDirecto((actuales) => actuales.filter((item) => item.numero !== tira.numero))} disabled={guardandoPedidoDirecto}>Quitar</button></article>) : <p>Escanea o escribe la primera tira. Aún no se ha creado ningún pedido.</p>}
              </div>
              <div className="direct-order-summary"><strong>Conteo por producto</strong>{[...tirasPedidoDirecto.reduce((acumulado, tira) => acumulado.set(tira.idProducto, { nombre: tira.producto, cantidad: (acumulado.get(tira.idProducto)?.cantidad || 0) + tira.imeis.length }), new Map()).values()].map((item) => <span key={item.nombre}>{item.nombre}: <b>{item.cantidad}</b></span>)}</div>
              <div className="direct-order-tigo">
                <label htmlFor="direct-tigo-amount">Tigo Money (opcional, sin IMEI)</label>
                <div className="direct-order-tigo-controls"><input id="direct-tigo-amount" type="number" min="1" step="1" inputMode="numeric" value={efectivoTigoDirecto} onChange={(event) => { setEfectivoTigoDirecto(event.target.value); setTigoDirectoValidado(null); setErrorPedidoDirecto('') }} placeholder="Monto a entregar" disabled={guardandoPedidoDirecto || validandoTigoDirecto} /><button type="button" onClick={validarTigoMoneyDirectoActual} disabled={guardandoPedidoDirecto || validandoTigoDirecto || !efectivoTigoDirecto.trim()}>{validandoTigoDirecto ? 'Validando…' : 'Validar'}</button></div>
                {tigoDirectoValidado && <small className="direct-order-tigo-valid">✓ Monto validado. Disponible: {money.format(Number(tigoDirectoValidado.saldoDisponible))} · Saldo restante: {money.format(Number(tigoDirectoValidado.saldoRestante))}</small>}
                {efectivoTigoDirecto.trim() && !tigoDirectoValidado && !validandoTigoDirecto && <small>Valida este monto para habilitar la confirmación.</small>}
              </div>
              <label className="direct-order-observation">Observación (opcional)<textarea maxLength="50" rows="2" value={observacionPedidoDirecto} onChange={(event) => setObservacionPedidoDirecto(event.target.value)} placeholder="Motivo o referencia de la entrega" /><small>{observacionPedidoDirecto.length}/50</small></label>
              <div className="direct-order-footer"><button type="button" onClick={cerrarPedidoDirecto} disabled={guardandoPedidoDirecto || validandoTigoDirecto}>Cancelar</button><button className="primary" type="button" onClick={guardarPedidoDirecto} disabled={guardandoPedidoDirecto || validandoTigoDirecto || (!tirasPedidoDirecto.length && !efectivoTigoDirecto.trim()) || (efectivoTigoDirecto.trim() && (!tigoDirectoValidado?.valido || tigoDirectoValidado.montoPedido !== Number(efectivoTigoDirecto)))}>{guardandoPedidoDirecto ? 'Guardando…' : 'Confirmar entrega directa'}</button></div>
            </div>
          </section>
          <aside className="order-dialog direct-order-balance-dialog" aria-label="Saldo actual de la ruta">
            <div className="order-dialog-head"><div><p>INVENTARIO DE LA RUTA</p><h2>Saldo actual</h2><span>{rutaSeleccionada?.ruta} · {rutaSeleccionada?.tecnico}</span></div><button type="button" onClick={() => consultarSaldoRutaDirecto(rutaSeleccionada.idRuta)} disabled={cargandoSaldoRutaDirecto}>Actualizar</button></div>
            <div className="direct-order-balance-content">
              {cargandoSaldoRutaDirecto ? <div className="orders-message">Consultando saldo actual…</div>
                : errorSaldoRutaDirecto ? <div className="direct-order-balance-error"><span>{errorSaldoRutaDirecto}</span><button type="button" onClick={() => consultarSaldoRutaDirecto(rutaSeleccionada.idRuta)}>Reintentar</button></div>
                  : saldoRutaDirecto ? <>
                    <div className="direct-order-balance-summary"><div><span>Productos</span><strong>{integer.format(saldoRutaDirecto.totalProductos)}</strong></div><div><span>Unidades</span><strong>{integer.format(saldoRutaDirecto.totalUnidades)}</strong></div><div><span>Valor</span><strong>{money.format(Number(saldoRutaDirecto.valorTotal))}</strong></div></div>
                    {saldoRutaDirecto.productos.length ? <div className="route-balance-table"><div className="route-balance-row head"><span>Producto</span><span>Cantidad</span></div>{saldoRutaDirecto.productos.map((item) => <div className="route-balance-row" key={item.idProducto}><strong>{item.producto}</strong><b>{integer.format(item.cantidad)}</b></div>)}</div> : <div className="orders-message">Esta ruta no tiene saldo registrado.</div>}
                    <small>Saldo consultado en la base. Las tiras de esta entrega aún no lo modifican.</small>
                  </> : null}
            </div>
          </aside>
          </div>
        </div>
      )}

      {(pedidoSeleccionado || cargandoDetalle) && (
        <div className="order-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !cargandoDetalle) cerrarDetalleAlmacen() }}>
          <section className="order-dialog detail-dialog" role="dialog" aria-modal="true" aria-labelledby="warehouse-detail-title">
            <div className="order-dialog-head">
              <div><p>{pedidoSeleccionado?.directo ? 'ENTREGA DIRECTA' : 'VERIFICACIÓN DE PEDIDO'}</p><h2 id="warehouse-detail-title">{pedidoSeleccionado?.directo ? `${pedidoSeleccionado.ruta} · Lista Master` : `Pedido #${pedidoSeleccionado?.idPedido}`}</h2></div>
              <button type="button" aria-label="Cerrar" onClick={cerrarDetalleAlmacen}>×</button>
            </div>
            {cargandoDetalle ? (
              <div className="orders-message">Consultando detalle…</div>
            ) : (
              <div className="detail-content">
                <div className="warehouse-modal-technician">
                  <div><span>Técnico</span><strong>{pedidoSeleccionado?.tecnico}</strong></div>
                  {!pedidoSeleccionado?.directo && <div className="warehouse-technician-actions">
                    <button type="button" onClick={mostrarSaldoPedidoAlmacen}>{saldoPedidoAlmacenVisible ? 'Ocultar saldo' : 'Ver saldo'}</button>
                    <button type="button" onClick={mostrarPromedioPedidoAlmacen}>{promedioPedidoAlmacenVisible ? 'Ocultar promedio' : 'Ver promedio'}</button>
                  </div>}
                </div>
                {saldoPedidoAlmacenVisible && (
                  <section className="sales-average-panel warehouse-average-panel">
                    <div className="sales-average-head"><div><span>INVENTARIO DISPONIBLE</span><strong>Saldo actual de {saldoPedidoAlmacen?.ruta || pedidoSeleccionado?.ruta}</strong></div><small>{saldoPedidoAlmacen ? `${saldoPedidoAlmacen.totalProductos} producto(s) · ${saldoPedidoAlmacen.totalUnidades} unidad(es)` : 'Consulta de la ruta del pedido'}</small></div>
                    {cargandoSaldoPedidoAlmacen ? <div className="sales-average-message">Consultando saldo…</div>
                      : saldoPedidoAlmacenError ? <div className="sales-average-message error">{saldoPedidoAlmacenError}</div>
                        : !saldoPedidoAlmacen?.productos?.length ? <div className="sales-average-message">Esta ruta no tiene productos con saldo disponible.</div>
                          : <div className="route-balance-table"><div className="route-balance-row head"><span>Producto</span><span>Cantidad</span></div>{saldoPedidoAlmacen.productos.map((item) => <div className="route-balance-row" key={item.idProducto}><strong>{item.producto}</strong><b>{integer.format(item.cantidad)}</b></div>)}</div>}
                  </section>
                )}
                {promedioPedidoAlmacenVisible && (
                  <section className="sales-average-panel warehouse-average-panel">
                    <div className="sales-average-head"><div><span>REFERENCIA PARA APROBACIÓN</span><strong>Promedio de venta de la ruta del técnico</strong></div><small>Mismo día de la semana del mes anterior</small></div>
                    {cargandoPromedioPedidoAlmacen ? <div className="sales-average-message">Calculando promedio…</div>
                      : promedioPedidoAlmacenError ? <div className="sales-average-message error">{promedioPedidoAlmacenError}</div>
                        : promediosPedidoAlmacen.length === 0 ? <div className="sales-average-message">No existen ventas históricas suficientes para esta ruta.</div>
                          : <div className="sales-average-table"><div className="sales-average-row head"><span>Producto</span><span>Promedio</span><span>Diferencia</span></div>{promediosPedidoAlmacen.map((item) => { const diferencia = Number(item.diferencia); return <div className="sales-average-row" key={item.idProducto}><strong>{item.producto}</strong><span>{item.promedioVenta}</span><b className={diferencia < 0 ? 'negative' : 'positive'}>{item.diferencia}</b></div> })}</div>}
                    <p>La diferencia es promedio histórico menos saldo actual. Positivo: está por debajo del promedio; negativo: está por encima. Es solo informativo.</p>
                  </section>
                )}
                <div className="detail-meta"><span>{dateTime.format(new Date(pedidoSeleccionado.fechaRegistro))}</span><strong>{money.format(pedidoSeleccionado.total)}</strong></div>
                <div className="detail-observation"><span>Observación</span><strong>{pedidoSeleccionado?.observacion || 'Sin observación'}</strong></div>
                {pedidoSeleccionado?.modificadoPorAlmacen === 1 && <div className="warehouse-change-notice"><span>MODIFICADO POR ALMACÉN</span><strong>{pedidoSeleccionado.comentarioAlmacen}</strong></div>}
                {pedidoSeleccionado.estadoAprobado === 2 && <div className="confirmed-detail-tabs"><button className={vistaDetalle === 'pedido' ? 'active' : ''} type="button" onClick={() => setVistaDetalle('pedido')}>Detalle pedido</button><button className={vistaDetalle === 'asignados' ? 'active' : ''} type="button" onClick={() => setVistaDetalle('asignados')}>Productos asignados <b>{productosAsignados.length}</b></button></div>}
                {vistaDetalle === 'pedido' || pedidoSeleccionado.estadoAprobado !== 2 ? <div className="detail-table">
                  <div className="detail-row detail-row--head"><span>Producto</span><span>Tipo</span><span>Cant.</span><span>Precio</span><span>Subtotal</span></div>
                  {detallePedido.map((detalle) => (
                    <div className={`detail-row ${editandoPedidoAlmacen && Number(cantidadesPedidoAlmacen[detalle.idDetalle]) === 0 ? 'warehouse-detail-removed' : ''}`} key={detalle.idDetalle}><strong>{detalle.producto}</strong><span>{detalle.tipoProducto || 'Sin tipo'}</span>{editandoPedidoAlmacen && pedidoSeleccionado.estadoAprobado === 1 ? <span className="warehouse-quantity-edit"><input type="number" min="0" max={detalle.cantidad} step="1" value={cantidadesPedidoAlmacen[detalle.idDetalle] ?? detalle.cantidad} onChange={(event) => setCantidadesPedidoAlmacen((actual) => ({ ...actual, [detalle.idDetalle]: event.target.value }))} /><small>máx. {detalle.cantidad}</small><button type="button" onClick={() => setCantidadesPedidoAlmacen((actual) => ({ ...actual, [detalle.idDetalle]: Number(actual[detalle.idDetalle]) === 0 ? detalle.cantidad : 0 }))}>{Number(cantidadesPedidoAlmacen[detalle.idDetalle]) === 0 ? 'Restaurar' : 'Eliminar'}</button></span> : <span>{detalle.cantidad}</span>}<span>{money.format(detalle.precio)}</span><span>{money.format(editandoPedidoAlmacen ? detalle.precio * Number(cantidadesPedidoAlmacen[detalle.idDetalle] ?? detalle.cantidad) : detalle.totalParcial)}</span></div>
                  ))}
                </div> : <div className="confirmed-master-list">
                  <div className="confirmed-master-head"><div><span>LISTA GENERAL</span><strong>Lista Master del pedido</strong></div><b>{tirasConfirmadas.length} tira(s) · {productosAsignados.length} IMEI</b></div>
                  {tirasConfirmadas.length ? tirasConfirmadas.map((tira) => <article className="confirmed-master-strip" key={tira.key}>
                    <div className="confirmed-strip-head"><div><span>{tira.producto}</span><strong>Tira {tira.numero}</strong><small>{tira.tipoProducto || 'Sin tipo'} · {tira.modo === 'rango' ? 'Primer y último' : tira.modo === 'cantidad' ? 'Por cantidad' : 'Uno por uno'}</small></div><b>{tira.imeis.length} unidades</b></div>
                    <div className="confirmed-strip-range"><code>{tira.imeis[0]}</code>{tira.imeis.length > 1 && <><span>—</span><code>{tira.imeis.at(-1)}</code></>}</div>
                    <details><summary>Ver todos los IMEI</summary><div>{tira.imeis.map((imei, index) => <code key={imei}><b>{index + 1}</b>{imei}</code>)}</div></details>
                  </article>) : <div className="assigned-products-empty">Este pedido confirmado no tiene una Lista Master registrada.</div>}
                </div>}
                {pedidoSeleccionado.estadoAprobado === 1 ? (
                  <>
                    {!pedidoSeleccionado.directo && <section className="warehouse-order-modification">
                      {!editandoPedidoAlmacen ? <div><p><span>AJUSTE DE ALMACÉN</span><strong>¿No hay existencia para completar todo el pedido?</strong><small>Disminuye cantidades o elimina productos y registra el motivo antes de aprobar.</small></p><button type="button" onClick={iniciarModificacionPedidoAlmacen}>Modificar pedido</button></div> : <div className="warehouse-modification-form"><label htmlFor="comentario-almacen">Motivo de la modificación<textarea id="comentario-almacen" maxLength="250" rows="3" value={comentarioPedidoAlmacen} onChange={(event) => setComentarioPedidoAlmacen(event.target.value)} placeholder="Ej.: Producto sin existencia en almacén" /></label><small>{comentarioPedidoAlmacen.length}/250 caracteres</small><p>Puedes disminuir cantidades o eliminar una línea completa. El pedido debe conservar al menos un producto.</p><div><button type="button" onClick={cancelarModificacionPedidoAlmacen} disabled={guardandoPedidoAlmacen}>Cancelar</button><button type="button" onClick={guardarModificacionPedidoAlmacen} disabled={guardandoPedidoAlmacen}>{guardandoPedidoAlmacen ? 'Guardando…' : 'Guardar modificación'}</button></div></div>}
                    </section>}
                    <section className="physical-products-section">
                      <div className="physical-products-heading"><div><span>PRODUCTOS DEL PEDIDO</span><strong>Valida Tigo Money y asigna los productos físicos</strong></div><b>{totalListaMaster} / {totalProductosPedido}</b></div>
                      {detallesFisicos.length > 0 && (!vinculoScanner ? (
                        <div className="order-scanner-link"><p>Vincula un teléfono para comenzar a escanear.</p><button type="button" onClick={crearVinculoScanner} disabled={creandoVinculo}>{creandoVinculo ? 'Generando…' : 'Vincular teléfono'}</button>{qrVinculoScanner && <img src={qrVinculoScanner} alt="QR de vinculacion" />}</div>
                      ) : (
                        <div className="order-scanner-status"><span /> Teléfono vinculado · {String(Math.floor(segundosScanner / 60)).padStart(2, '0')}:{String(segundosScanner % 60).padStart(2, '0')} {qrVinculoScanner && <img src={qrVinculoScanner} alt="QR para abrir el lector" />}</div>
                      ))}
                      <div className="physical-line-list">
                        {detallesTigoMoney.map((detalle) => {
                          const validacion = tigoMoneyValidado[detalle.idDetalle]
                          const validado = Boolean(validacion)
                          const validando = validandoTigoMoney === detalle.idDetalle
                          return <article className={validado ? 'complete' : ''} key={detalle.idDetalle}>
                            <div><strong>{detalle.producto}</strong><small>{detalle.tipoProducto || 'TigoMoney'} · Detalle #{detalle.idDetalle}</small></div>
                            <span>{validado ? detalle.cantidad : 0} / {detalle.cantidad}</span>
                            <b>{validado ? 'VALIDADO' : 'PENDIENTE'}</b>
                            <button type="button" onClick={() => validarTigoMoneyPedido(detalle)} disabled={validando || validado}>{validando ? 'Validando…' : validado ? 'Validado' : 'Validar'}</button>
                          </article>
                        })}
                        {detallesFisicos.map((detalle) => {
                          const cargados = imeisAsignadosDetalle(detalle.idDetalle).length
                          const completo = cargados === detalle.cantidad
                          return <article className={`${detalleEscaneo?.idDetalle === detalle.idDetalle ? 'active' : ''} ${completo ? 'complete' : ''}`} key={detalle.idDetalle}>
                            <div><strong>{detalle.producto}</strong><small>{detalle.tipoProducto || 'Sin tipo'} · Detalle #{detalle.idDetalle}</small></div>
                            <span>{cargados} / {detalle.cantidad}</span>
                            <b>{completo ? 'COMPLETO' : 'PENDIENTE'}</b>
                            <div className="physical-line-actions">
                              <button type="button" onClick={() => activarCapturaDetalle(detalle)} disabled={!vinculoScanner || completo}>{completo ? 'Cargado' : detalleEscaneo?.idDetalle === detalle.idDetalle && !ingresoManualPedido ? 'Escaneando' : 'Cámara'}</button>
                              <button type="button" onClick={() => activarCapturaManual(detalle)} disabled={completo}>{detalleEscaneo?.idDetalle === detalle.idDetalle && ingresoManualPedido ? 'Manual activo' : 'Ingresar a mano'}</button>
                            </div>
                          </article>
                        })}
                      </div>
                      {detalleEscaneo && (
                        <div className="order-scan-workspace">
                          <div className="order-scan-head"><div><span>LISTA MASTER · {detalleEscaneo.producto}</span><strong>Tira {(asignacionesPedido[detalleEscaneo.idDetalle]?.length || 0) + 1}</strong></div><b>{imeisAsignadosDetalle(detalleEscaneo.idDetalle).length} / {detalleEscaneo.cantidad}</b></div>
                          <div className="strip-mode-selector">
                            <button className={modoTiraPedido === 'individual' ? 'active' : ''} type="button" onClick={() => limpiarTiraPedido('individual')}>Uno por uno</button>
                            <button className={modoTiraPedido === 'rango' ? 'active' : ''} type="button" onClick={() => limpiarTiraPedido('rango')}>Primer y último</button>
                            <button className={modoTiraPedido === 'cantidad' ? 'active' : ''} type="button" onClick={() => { setIngresoManualPedido(true); limpiarTiraPedido('cantidad') }}>Por cantidad</button>
                          </div>
                          <p>{modoTiraPedido === 'cantidad'
                            ? 'Confirma el primer IMEI e indica la cantidad. Al agregar la tira se calcularán y validarán en la base todos los IMEI consecutivos antes de incorporarlos a la Lista Master.'
                            : ingresoManualPedido
                              ? (modoTiraPedido === 'individual' ? 'Ingresa y confirma cada IMEI antes de agregar la tira.' : 'Confirma primero el IMEI inicial y después el final. Al agregar la tira se validará también todo el rango intermedio.')
                              : (modoTiraPedido === 'individual' ? 'Escanea todas las unidades de la tira.' : 'Escanea el primer y el último IMEI; el sistema validará también todos los intermedios.')}</p>
                          {ingresoManualPedido && <div className="manual-imei-entry">
                            <div className="manual-entry-toolbar"><span>INGRESO MANUAL</span><button type="button" onClick={() => activarCapturaDetalle(detalleEscaneo)} disabled={!vinculoScanner}>Escanear con cámara</button></div>
                            {modoTiraPedido === 'rango' ? <div className="manual-range-flow">
                              <label className={imeiManualPrimeroValidado ? 'validated' : ''}>1. Primer IMEI<div><input inputMode="numeric" value={imeiManualPrimero} onChange={(event) => { setImeiManualPrimero(event.target.value); setImeiManualPrimeroValidado(false); setImeiManualUltimo(''); setImeiManualUltimoValidado(false); setLecturasTiraPedido([]); setImeisRevisionTiraPedido(null) }} placeholder="IMEI inicial" disabled={validandoImeiManual} /><button type="button" onClick={() => confirmarExtremoManual('primero')} disabled={validandoImeiManual || !imeiManualPrimero.trim()}>{imeiManualPrimeroValidado ? 'Confirmado' : 'Confirmar'}</button></div>{imeiManualPrimeroValidado && <small>IMEI inicial válido</small>}</label>
                              <label className={imeiManualUltimoValidado ? 'validated' : ''}>2. Último IMEI<div><input inputMode="numeric" value={imeiManualUltimo} onChange={(event) => { setImeiManualUltimo(event.target.value); setImeiManualUltimoValidado(false); setLecturasTiraPedido([]); setImeisRevisionTiraPedido(null) }} placeholder={imeiManualPrimeroValidado ? 'IMEI final' : 'Confirma primero el IMEI inicial'} disabled={!imeiManualPrimeroValidado || validandoImeiManual} /><button type="button" onClick={() => confirmarExtremoManual('ultimo')} disabled={!imeiManualPrimeroValidado || validandoImeiManual || !imeiManualUltimo.trim()}>{imeiManualUltimoValidado ? 'Confirmado' : 'Confirmar'}</button></div>{imeiManualUltimoValidado && <small>IMEI final válido; la tira está lista para su validación completa</small>}</label>
                            </div> : modoTiraPedido === 'cantidad' ? <div className="manual-range-flow">
                              <label className={imeiManualPrimeroValidado ? 'validated' : ''}>1. Primer IMEI<div><input inputMode="numeric" value={imeiManualPrimero} onChange={(event) => { setImeiManualPrimero(event.target.value); setImeiManualPrimeroValidado(false); setCantidadManualTira(''); setLecturasTiraPedido([]); setImeisRevisionTiraPedido(null) }} placeholder="IMEI inicial" disabled={validandoImeiManual} /><button type="button" onClick={() => confirmarExtremoManual('primero')} disabled={validandoImeiManual || !imeiManualPrimero.trim()}>{imeiManualPrimeroValidado ? 'Confirmado' : 'Confirmar'}</button></div>{imeiManualPrimeroValidado && <small>IMEI inicial válido en la base de datos</small>}</label>
                              <label>2. Cantidad<div><input type="number" inputMode="numeric" min="1" max="1000" step="1" value={cantidadManualTira} onChange={(event) => { setCantidadManualTira(event.target.value); setImeisRevisionTiraPedido(null) }} placeholder={imeiManualPrimeroValidado ? 'Ej.: 500' : 'Confirma primero el IMEI inicial'} disabled={!imeiManualPrimeroValidado || validandoImeiManual} /></div>{imeiManualPrimeroValidado && <small>Se generarán IMEI consecutivos desde el inicial. Todos se validarán al agregar la tira.</small>}</label>
                            </div> : <div className="manual-individual-flow"><label>IMEI<div><input inputMode="numeric" value={imeisManuales} onChange={(event) => setImeisManuales(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') confirmarImeiManualIndividual() }} placeholder="Ingresa un IMEI" disabled={validandoImeiManual} /><button type="button" onClick={confirmarImeiManualIndividual} disabled={validandoImeiManual || !imeisManuales.trim()}>{validandoImeiManual ? 'Validando…' : 'Confirmar IMEI'}</button></div></label>{imeisManualesConfirmados.length > 0 && <div className="manual-confirmed-list">{imeisManualesConfirmados.map((imei, index) => <span key={imei}><b>{index + 1}</b><code>{imei}</code><button type="button" onClick={() => quitarImeiManualConfirmado(imei)}>Quitar</button></span>)}</div>}</div>}
                            {validandoImeiManual && <small className="manual-validating">Validando en la base de datos…</small>}
                          </div>}
                          {listaScannerCerrada && <div className="order-scan-note">{ingresoManualPedido ? 'Códigos confirmados. Revisa y agrega la tira a la Lista Master.' : 'Tira cerrada desde el teléfono. Revísala y agrégala a la Lista Master.'}</div>}
                          <div className="order-scan-readings">{lecturasTiraPedido.length ? lecturasTiraPedido.map((item, index) => <span key={item.id}><b>{index + 1}</b>{item.codigo}</span>) : <small>{ingresoManualPedido ? 'Ingresa y confirma los códigos de la tira.' : 'Esperando lecturas válidas desde el teléfono…'}</small>}</div>
                          {imeisRevisionTiraPedido && <div className="order-strip-information"><div><strong>Información de la tira</strong><span>{imeisRevisionTiraPedido.length} IMEI listos para agregar</span></div>{imeisRevisionTiraPedido.length ? <div className="order-strip-information-list">{imeisRevisionTiraPedido.map((imei, index) => <span key={imei}><b>{index + 1}</b><code>{imei}</code><button type="button" onClick={() => eliminarImeiRevisionTiraPedido(imei)} aria-label={`Eliminar IMEI ${imei}`}>Eliminar</button></span>)}</div> : <small>Eliminaste todos los IMEI. Revisa la tira o límpiala para comenzar de nuevo.</small>}</div>}
                          <div className="order-scan-actions"><button type="button" onClick={() => limpiarTiraPedido()} disabled={!lecturasTiraPedido.length}>Limpiar</button><button type="button" onClick={mostrarInformacionTiraPedido} disabled={!lecturasTiraPedido.length || validandoTiraPedido || (modoTiraPedido === 'cantidad' && !cantidadManualTira)}>Información</button><button type="button" onClick={agregarTiraPedido} disabled={!lecturasTiraPedido.length || validandoTiraPedido || imeisRevisionTiraPedido?.length === 0 || (modoTiraPedido === 'cantidad' && !cantidadManualTira)}>{validandoTiraPedido ? 'Validando…' : 'Validar y agregar tira'}</button></div>
                          <div className="order-master-strips">{(asignacionesPedido[detalleEscaneo.idDetalle] || []).map((tira) => <article key={tira.id}><div><strong>Tira {tira.numero}</strong><small>{tira.imeis.length} unidades · {tira.imeis[0]} — {tira.imeis.at(-1)}</small></div><b>VÁLIDA</b><button type="button" onClick={() => quitarTiraPedido(detalleEscaneo.idDetalle, tira.id)}>Quitar</button></article>)}</div>
                        </div>
                      )}
                      {scannerPedidoError && <div className="scanner-message scanner-message--error">{scannerPedidoError}</div>}
                    </section>
                    <section className="pending-master-preview">
                      <div className="confirmed-master-head">
                        <div><span>PRELIMINAR DE ENVÍO</span><strong>Detalle de Lista Master</strong></div>
                        <b>{tirasListaMaster.length + tigoMoneyListaMaster.length} registro(s) · {totalListaMaster} producto(s)</b>
                      </div>
                      <div className="pending-master-summary">
                        <span className={productosFisicosCompletos ? 'complete' : ''} />
                        <p><strong>{productosFisicosCompletos ? 'Lista completa para aprobar' : 'Lista en preparación'}</strong><small>Se enviarán exactamente las tiras mostradas a continuación.</small></p>
                        <b>{totalListaMaster} / {totalProductosPedido}</b>
                      </div>
                      {tirasListaMaster.length ? <div className="pending-master-strips">{tirasListaMaster.map((tira) => (
                        <article className="confirmed-master-strip" key={`${tira.idDetalle}-${tira.id}`}>
                          <div className="confirmed-strip-head">
                            <div><span>{tira.producto}</span><strong>Tira {tira.numero}</strong><small>{tira.tipoProducto || 'Sin tipo'} · {tira.modo === 'rango' ? 'Primer y último' : tira.modo === 'cantidad' ? 'Por cantidad' : 'Uno por uno'} · Detalle #{tira.idDetalle}</small></div>
                            <b>{tira.imeis.length} unidades</b>
                          </div>
                          <div className="confirmed-strip-range"><code>{tira.imeis[0]}</code>{tira.imeis.length > 1 && <><span>—</span><code>{tira.imeis.at(-1)}</code></>}</div>
                          <details><summary>Ver los {tira.imeis.length} códigos de esta tira</summary><div>{tira.imeis.map((imei, index) => <code key={`${imei}-${index}`}><b>{index + 1}</b>{imei}</code>)}</div></details>
                        </article>
                      ))}</div> : !tigoMoneyListaMaster.length && <div className="assigned-products-empty">Valida Tigo Money o agrega las tiras físicas para completar la Lista Master.</div>}
                      {tigoMoneyListaMaster.length > 0 && <div className="pending-master-strips">{tigoMoneyListaMaster.map((detalle) => {
                        const validacion = tigoMoneyValidado[detalle.idDetalle]
                        return <article className="confirmed-master-strip" key={`tigo-${detalle.idDetalle}`}>
                          <div className="confirmed-strip-head">
                            <div><span>{detalle.producto}</span><strong>Saldo validado</strong><small>Sin escaneo · Cod. inicio 0 · Cod. final 0 · Detalle #{detalle.idDetalle}</small></div>
                            <b>{detalle.cantidad} unidades</b>
                          </div>
                          <div className="confirmed-strip-range"><code>Disponible: Bs {Number(validacion.saldoDisponible).toLocaleString('es-BO')}</code><span>—</span><code>Restante: Bs {Number(validacion.saldoRestante).toLocaleString('es-BO')}</code></div>
                        </article>
                      })}</div>}
                    </section>
                    <div className="approval-controls">
                      {pedidoSeleccionado.directo ? <div className="direct-approval-label"><span>ASIGNACIÓN INMEDIATA</span><strong>Se registrará directamente en pedido y almacén vendedor.</strong></div> : <label htmlFor="fecha-entrega">Fecha de entrega<input id="fecha-entrega" type="date" min={hoy} value={fechaEntrega} onChange={(event) => setFechaEntrega(event.target.value)} required /></label>}
                      <div><button type="button" onClick={cerrarDetalleAlmacen}>Cancelar</button><button type="button" onClick={aprobarPedido} disabled={(!pedidoSeleccionado.directo && !fechaEntrega) || !productosFisicosCompletos}>{productosFisicosCompletos ? (pedidoSeleccionado.directo ? 'Crear y asignar pedido' : 'Aprobar pedido') : 'Completa los productos'}</button></div>
                    </div>
                  </>
                ) : (
                  <div className="approved-info"><span>Pedido aprobado por</span><strong>{pedidoSeleccionado.aprobadoPor || 'No registrado'}</strong></div>
                )}
              </div>
            )}
          </section>
        </div>
      )}
      {tutorialAbierto && <GuidedTour onClose={() => setTutorialAbierto(false)} steps={[
        { target: '[data-tour="warehouse-brand"]', title: 'Centro de operaciones de almacén', description: 'Este recorrido es completamente informativo. No aprobará pedidos, no modificará cuadres y no cambiará inventario.' },
        { target: '[data-tour="warehouse-orders"]', title: 'Pedidos pendientes por ruta', description: 'Mock de capacitación para explicar cómo priorizar rutas, abrir pedidos y revisar técnico/estado.', mock: 'warehouse-orders' },
        { target: '[data-tour="warehouse-orders"]', title: 'Detalle y aprobación', description: 'Mock interactivo de carga de IMEI y habilitación de aprobación cuando el pedido está completo.', mock: 'warehouse-approval' },
        { target: '[data-tour="warehouse-cashups"]', title: 'Revisión de cuadres', description: 'El contador muestra los cuadres enviados por vendedores. Puedes verificar la versión original, aprobarla o registrar una versión modificada.', mock: 'warehouse-cashup' },
        { target: '[data-tour="warehouse-devices"]', title: 'Vincular dispositivo', description: 'Flujo guiado de token, QR, vinculación y lecturas SSE; todo en modo simulación.', mock: 'warehouse-linking' },
        { target: '[data-tour="warehouse-statistics"]', title: 'Estadísticas', description: 'Consulta pedidos realizados, aprobados y modificados, organizados por fecha y ruta.' },
        { target: '.warehouse-workbench', title: 'Todo listo', description: 'Los contadores te avisan qué requiere atención. Puedes volver a abrir este tutorial cuando quieras desde el menú lateral.' },
      ]} />}
    </main>
  )
}

function AccountingDashboard({ session, onLogout }) {
  const { usuario } = session
  const [depositos, setDepositos] = useState([])
  const [entidades, setEntidades] = useState([])
  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState('')
  const [filtro, setFiltro] = useState('todos')
  const [busqueda, setBusqueda] = useState('')
  const [editando, setEditando] = useState(null)
  const [detalleDeposito, setDetalleDeposito] = useState(null)
  const [aprobando, setAprobando] = useState(null)
  const [formulario, setFormulario] = useState({ idEntidad: '', cuenta: '', monto: '', op: '' })
  const [guardando, setGuardando] = useState(false)
  const headers = { Authorization: `Bearer ${session.token}` }

  const cargar = async () => {
    setCargando(true); setError('')
    try {
      const [lista, bancos] = await Promise.all([
        api('/api/auth/contabilidad/depositos-pendientes', { headers }),
        api('/api/auth/entidades', { headers }),
      ])
      setDepositos(lista); setEntidades(bancos)
    } catch (err) { setError(err.message) } finally { setCargando(false) }
  }

  useEffect(() => { cargar() }, [session.token])

  const pendientes = depositos.filter((item) => item.estadoAprobacion === 2)
  const aprobados = depositos.filter((item) => item.estadoAprobacion === 3)
  const sinOp = pendientes.filter((item) => item.puedeEditar).length
  const montoPendiente = pendientes.reduce((total, item) => total + Number(item.monto || 0), 0)
  const montoAprobado = aprobados.reduce((total, item) => total + Number(item.monto || 0), 0)
  const visibles = depositos.filter((item) => {
    if (filtro === 'pendientes' && item.estadoAprobacion !== 2) return false
    if (filtro === 'aprobados' && item.estadoAprobacion !== 3) return false
    if (filtro === 'sin_op' && !item.puedeEditar) return false
    const texto = `${item.idDeposito} ${item.ruta} ${item.vendedor} ${item.nombreBanco} ${item.cuenta} ${item.op || ''}`.toLowerCase()
    return texto.includes(busqueda.trim().toLowerCase())
  })

  const abrirEdicion = (deposito) => {
    if (!deposito.puedeEditar) return
    setFormulario({ idEntidad: String(deposito.idEntidad), cuenta: deposito.cuenta || '', monto: String(deposito.monto || ''), op: deposito.op || '' })
    setEditando(deposito); setError('')
  }

  const guardar = async (event) => {
    event.preventDefault(); setGuardando(true); setError('')
    try {
      await api(`/api/auth/contabilidad/depositos/${editando.idDeposito}`, {
        method: 'PUT', headers,
        body: JSON.stringify({ idEntidad: Number(formulario.idEntidad), cuenta: formulario.cuenta.trim(), monto: Number(formulario.monto), op: formulario.op.trim() || null }),
      })
      setEditando(null); await cargar()
    } catch (err) { setError(err.message) } finally { setGuardando(false) }
  }

  const aprobar = async (deposito) => {
    if (!deposito.op?.trim()) { setError('Completa la OP antes de aprobar el depósito.'); return }
    if (!window.confirm(`¿Aprobar el depósito #${deposito.idDeposito} por ${money.format(deposito.monto)}?`)) return
    setAprobando(deposito.idDeposito); setError('')
    try {
      await api(`/api/auth/contabilidad/depositos/${deposito.idDeposito}/aprobar`, { method: 'POST', headers })
      setDetalleDeposito(null); await cargar()
    } catch (err) { setError(err.message) } finally { setAprobando(null) }
  }

  const initials = usuario.nombre.split(/\s+/).slice(0, 2).map((parte) => parte[0]).join('').toUpperCase()
  return <main className="accounting-page">
    <header className="topbar accounting-topbar"><div className="topbar-brand"><BrandMark /><span>Control de Contabilidad</span></div><div className="topbar-user"><div className="avatar">{initials}</div><div><strong>{usuario.nombre}</strong><span>{usuario.sucursal.nombre}</span></div><button type="button" onClick={onLogout}>Cerrar sesión</button></div></header>
    <div className="accounting-shell"><aside className="accounting-sidebar"><p>MENÚ</p><h2>Contabilidad</h2><button className="active" type="button"><span>D</span><div><strong>Control de depósitos</strong><small>Pendientes e históricos</small></div>{pendientes.length > 0 && <b>{pendientes.length}</b>}</button><div className="accounting-session"><i /><strong>Sistema conectado</strong><small>{usuario.sucursal.nombre}</small></div></aside>
      <section className="accounting-workspace"><header className="accounting-heading"><div><p>CONTROL DE DEPÓSITOS</p><h1>Depósitos de las rutas</h1><span>Revisa los pendientes y consulta el historial de depósitos ya aprobados.</span></div><button type="button" onClick={cargar}>Actualizar</button></header>
        <div className="accounting-kpis"><article><span>Pendientes</span><strong>{integer.format(pendientes.length)}</strong><small>{money.format(montoPendiente)} por revisar</small></article><article className="warning"><span>Pendientes sin OP</span><strong>{integer.format(sinOp)}</strong><small>Disponibles para editar</small></article><article className="approved"><span>Aprobados históricos</span><strong>{integer.format(aprobados.length)}</strong><small>Registros finalizados</small></article><article className="money"><span>Monto aprobado</span><strong>{money.format(montoAprobado)}</strong><small>Total histórico aprobado</small></article></div>
        <section className="accounting-card"><div className="accounting-toolbar"><div><button className={filtro === 'todos' ? 'active' : ''} onClick={() => setFiltro('todos')}>Todos <b>{depositos.length}</b></button><button className={filtro === 'pendientes' ? 'active' : ''} onClick={() => setFiltro('pendientes')}>Pendientes <b>{pendientes.length}</b></button><button className={filtro === 'sin_op' ? 'active' : ''} onClick={() => setFiltro('sin_op')}>Sin OP <b>{sinOp}</b></button><button className={filtro === 'aprobados' ? 'active' : ''} onClick={() => setFiltro('aprobados')}>Aprobados <b>{aprobados.length}</b></button></div><label><span>⌕</span><input type="search" placeholder="Buscar ruta, vendedor, banco o cuenta…" value={busqueda} onChange={(event) => setBusqueda(event.target.value)} /></label></div>
          {error && !editando && <div className="accounting-message error">{error}</div>}{cargando ? <div className="accounting-message">Consultando depósitos…</div> : visibles.length === 0 ? <div className="accounting-message">No existen depósitos con este filtro.</div> : <div className="accounting-table-scroll"><table><thead><tr><th>Depósito</th><th>Ruta / vendedor</th><th>Banco</th><th>Cuenta</th><th>Monto</th><th>OP</th><th>Estado</th><th>Registro</th><th>Acciones</th></tr></thead><tbody>{visibles.map((item) => <tr key={item.idDeposito} className={item.estadoAprobacion === 3 ? 'accounting-row-approved' : ''}><td><strong>#{item.idDeposito}</strong></td><td><strong>{item.ruta}</strong><small>{item.vendedor}</small></td><td>{item.nombreBanco}</td><td><code>{item.cuenta}</code></td><td><b>{money.format(item.monto)}</b></td><td>{item.op ? <span className="accounting-op complete">{item.op}</span> : <span className="accounting-op missing">SIN OP</span>}</td><td><span className={`accounting-status ${item.estadoAprobacion === 3 ? 'approved' : 'pending'}`}>{item.estadoTexto}</span></td><td>{dateTime.format(new Date(item.fechaRegistro))}{item.fechaAprobacion && <small>Aprobado: {dateTime.format(new Date(item.fechaAprobacion))}</small>}</td><td><div className="accounting-actions"><button className="detail" type="button" onClick={() => setDetalleDeposito(item)}>Ver detalle</button>{item.puedeEditar ? <><button className="accounting-edit" type="button" onClick={() => abrirEdicion(item)}>Editar</button><button className="approve" type="button" disabled title="Completa la OP antes de aprobar">Aprobar</button></> : item.puedeAprobar ? <button className="approve" type="button" disabled={aprobando === item.idDeposito} onClick={() => aprobar(item)}>{aprobando === item.idDeposito ? 'Aprobando…' : 'Aprobar'}</button> : <span className="accounting-locked">Finalizado</span>}</div></td></tr>)}</tbody></table></div>}
        </section>
      </section>
    </div>
    {detalleDeposito && <div className="order-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !aprobando) setDetalleDeposito(null) }}><section className="accounting-dialog accounting-detail-dialog"><header><div><p>DETALLE DEL DEPÓSITO</p><h2>Depósito #{detalleDeposito.idDeposito}</h2><span>{detalleDeposito.estadoAprobacion === 3 ? 'Depósito aprobado y finalizado' : 'Pendiente de aprobación de Contabilidad'}</span></div><button type="button" disabled={Boolean(aprobando)} onClick={() => setDetalleDeposito(null)}>×</button></header><div className="accounting-detail-person"><div><span>Ruta</span><strong>{detalleDeposito.ruta}</strong></div><div><span>Vendedor</span><strong>{detalleDeposito.vendedor}</strong></div><div><span>Registrado</span><strong>{dateTime.format(new Date(detalleDeposito.fechaRegistro))}</strong></div></div><div className="accounting-detail-data"><div><span>Banco</span><strong>{detalleDeposito.nombreBanco}</strong></div><div><span>Cuenta</span><strong>{detalleDeposito.cuenta}</strong></div><div><span>Monto</span><strong>{money.format(detalleDeposito.monto)}</strong></div><div><span>OP</span>{detalleDeposito.op ? <strong>{detalleDeposito.op}</strong> : <b>SIN OP</b>}</div></div>{detalleDeposito.estadoAprobacion === 3 && <div className="accounting-approval-audit"><strong>APROBADO</strong><span>Por {detalleDeposito.aprobadoPor || 'Contabilidad'}</span><time>{detalleDeposito.fechaAprobacion ? dateTime.format(new Date(detalleDeposito.fechaAprobacion)) : 'Fecha no registrada'}</time></div>}{detalleDeposito.estadoAprobacion === 2 && !detalleDeposito.op && <div className="accounting-edit-notice"><strong>No se puede aprobar todavía</strong><span>Este depósito debe editarse y completar su OP antes de aprobarlo.</span></div>}{error && <div className="accounting-message error">{error}</div>}{detalleDeposito.estadoAprobacion === 2 && <footer>{detalleDeposito.puedeEditar && <button type="button" onClick={() => { setDetalleDeposito(null); abrirEdicion(detalleDeposito) }}>Editar depósito</button>}{detalleDeposito.puedeAprobar && <button className="primary" type="button" disabled={!detalleDeposito.op?.trim() || Boolean(aprobando)} onClick={() => aprobar(detalleDeposito)}>{aprobando ? 'Aprobando…' : detalleDeposito.op?.trim() ? 'Aprobar depósito' : 'Falta completar OP'}</button>}</footer>}</section></div>}
    {editando && <div className="order-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !guardando) setEditando(null) }}><form className="accounting-dialog" onSubmit={guardar}><header><div><p>EDICIÓN CONTROLADA</p><h2>Depósito #{editando.idDeposito}</h2><span>{editando.ruta} · {editando.vendedor}</span></div><button type="button" disabled={guardando} onClick={() => setEditando(null)}>×</button></header><div className="accounting-edit-notice"><strong>Este depósito no tiene OP</strong><span>Al guardar una OP, el registro quedará protegido contra nuevas ediciones.</span></div>{error && <div className="accounting-message error">{error}</div>}<div className="accounting-form-grid"><label>Banco<select required value={formulario.idEntidad} onChange={(event) => setFormulario({ ...formulario, idEntidad: event.target.value })}>{entidades.map((item) => <option key={item.idEntidad} value={item.idEntidad}>{item.nombre}</option>)}</select></label><label>Cuenta<input required maxLength="50" value={formulario.cuenta} onChange={(event) => setFormulario({ ...formulario, cuenta: event.target.value })} /></label><label>Monto<input required min="0.01" step="0.01" type="number" value={formulario.monto} onChange={(event) => setFormulario({ ...formulario, monto: event.target.value })} /></label><label>OP<input maxLength="50" value={formulario.op} onChange={(event) => setFormulario({ ...formulario, op: event.target.value })} placeholder="Ingresa la OP si ya está disponible" /></label></div><footer><button type="button" disabled={guardando} onClick={() => setEditando(null)}>Cancelar</button><button className="primary" type="submit" disabled={guardando}>{guardando ? 'Guardando…' : 'Guardar cambios'}</button></footer></form></div>}
  </main>
}

const ETIQUETAS_TIPO_MOVIMIENTO = {
  CUADRE: 'Cuadre definitivo',
  CUADRE_PRELIMINAR: 'Cuadre preliminar',
  PEDIDO: 'Pedido en ruta',
}

const ETIQUETAS_TIPO_CORTAS = {
  CUADRE: 'CUADRE',
  CUADRE_PRELIMINAR: 'PRELIM.',
  PEDIDO: 'PEDIDO',
}

function PasswordResetAdminPanel({ session }) {
  const headers = useMemo(() => ({ Authorization: `Bearer ${session.token}` }), [session.token])
  const [roles, setRoles] = useState([])
  const [rolId, setRolId] = useState('')
  const [buscar, setBuscar] = useState('')
  const [vista, setVista] = useState('todos')
  const [usuarios, setUsuarios] = useState([])
  const [seleccionados, setSeleccionados] = useState([])
  const [cargando, setCargando] = useState(true)
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState('')
  const [aviso, setAviso] = useState('')
  const cargar = () => {
    setCargando(true)
    const qs = new URLSearchParams({ buscar })
    if (rolId) qs.set('rolId', rolId)
    api(`/api/auth/password/usuarios?${qs}`, { headers })
      .then(setUsuarios).catch((err) => setError(err.message)).finally(() => setCargando(false))
  }
  useEffect(() => { api('/api/auth/password/roles', { headers }).then(setRoles).catch((err) => setError(err.message)) }, [session.token])
  useEffect(() => { const timer = window.setTimeout(cargar, 250); return () => window.clearTimeout(timer) }, [session.token, buscar, rolId])
  const unicos = Array.from(new Map(usuarios.map((u) => [u.id, u])).values())
  const pendientes = unicos.filter((u) => u.pendiente)
  const visibles = vista === 'pendientes' ? pendientes : unicos
  const idsFiltrados = visibles.filter((u) => !u.pendiente).map((u) => u.id)
  const todosMarcados = idsFiltrados.length > 0 && idsFiltrados.every((id) => seleccionados.includes(id))
  const marcarTodos = () => setSeleccionados((actual) => todosMarcados
    ? actual.filter((id) => !idsFiltrados.includes(id))
    : [...new Set([...actual, ...idsFiltrados])])
  const marcar = (id) => setSeleccionados((actual) => actual.includes(id) ? actual.filter((x) => x !== id) : [...actual, id])
  const solicitar = async () => {
    if (!seleccionados.length || enviando) return
    if (!window.confirm(`¿Solicitar cambio de contraseña a ${seleccionados.length} usuario(s)?`)) return
    setEnviando(true); setError(''); setAviso('')
    try {
      const data = await api('/api/auth/password/solicitar', { method: 'POST', headers, body: JSON.stringify({ idsUsuario: seleccionados }) })
      setAviso(`${data.creadas} solicitud(es) creadas${data.yaPendientes ? `; ${data.yaPendientes} ya estaban pendientes` : ''}.`)
      setSeleccionados([]); setVista('pendientes'); cargar()
    } catch (err) { setError(err.message) } finally { setEnviando(false) }
  }
  return <section className="password-admin">
    <div className="password-admin-heading"><div><p>PANEL DE SISTEMAS</p><h2>Reinicio de contraseñas</h2><span>Selecciona usuarios activos. Se les pedirá crear una nueva contraseña al ingresar.</span></div><strong>{pendientes.length} pendiente(s) en esta vista</strong></div>
    <div className="password-admin-toolbar"><label>Rol<select value={rolId} onChange={(event) => setRolId(event.target.value)}><option value="">Todos los roles</option>{roles.map((rol) => <option key={rol.id} value={rol.id}>{rol.nombre}</option>)}</select></label><label>Buscar por nombre o usuario<input type="search" value={buscar} onChange={(event) => setBuscar(event.target.value)} placeholder="Ej. fcardona" /></label>{vista === 'todos' && <button type="button" onClick={marcarTodos} disabled={!idsFiltrados.length}>{todosMarcados ? 'Desmarcar visibles' : `Marcar visibles (${idsFiltrados.length})`}</button>}</div>
    <div className="password-admin-views"><button type="button" className={vista === 'todos' ? 'active' : ''} onClick={() => setVista('todos')}>Todos <b>{unicos.length}</b></button><button type="button" className={vista === 'pendientes' ? 'active' : ''} onClick={() => { setVista('pendientes'); setSeleccionados([]) }}>Pendientes de cambio <b>{pendientes.length}</b></button><button type="button" className="password-admin-refresh" onClick={cargar} disabled={cargando}>Actualizar</button></div>
    {error && <div className="password-admin-error">{error}</div>}{aviso && <div className="password-admin-success">{aviso}</div>}
    <div className="password-admin-table"><table><thead><tr>{vista === 'todos' && <th>Seleccionar</th>}<th>Usuario</th><th>Login</th><th>Rol(es)</th><th>Estado</th></tr></thead><tbody>{cargando ? <tr><td colSpan={vista === 'todos' ? 5 : 4}>Consultando usuarios…</td></tr> : visibles.length === 0 ? <tr><td colSpan={vista === 'todos' ? 5 : 4}>{vista === 'pendientes' ? 'No hay cambios de contraseña pendientes con estos filtros.' : 'No hay usuarios con estos filtros.'}</td></tr> : visibles.map((u) => <tr key={u.id}>{vista === 'todos' && <td><input type="checkbox" aria-label={`Seleccionar ${u.nombre}`} checked={seleccionados.includes(u.id)} disabled={u.pendiente} onChange={() => marcar(u.id)} /></td>}<td><strong>{u.nombre}</strong><small>#{u.id}</small></td><td>{u.loggin}</td><td>{[...new Set(usuarios.filter((item) => item.id === u.id).map((item) => item.rol).filter(Boolean))].join(', ') || 'Sin rol'}</td><td><span className={u.pendiente ? 'password-admin-pending' : 'password-admin-clear'}>{u.pendiente ? 'Cambio pendiente' : 'Activo'}</span></td></tr>)}</tbody></table></div>
    {vista === 'todos' && <div className="password-admin-footer"><span>{seleccionados.length} seleccionado(s)</span><button type="button" onClick={() => setSeleccionados([])} disabled={!seleccionados.length}>Limpiar selección</button><button type="button" className="primary" onClick={solicitar} disabled={!seleccionados.length || enviando}>{enviando ? 'Guardando…' : 'Solicitar cambio de contraseña'}</button></div>}
  </section>
}

function SystemsDashboard({ session, onLogout }) {
  const { usuario } = session
  const headers = { Authorization: `Bearer ${session.token}` }
  const initials = usuario.nombre.split(/\s+/).slice(0, 2).map((parte) => parte[0]).join('').toUpperCase()
  const hoy = new Date().toISOString().slice(0, 10)
  const inicioMes = `${hoy.slice(0, 7)}-01`
  const inicioHistorico = '2000-01-01'

  const [rutas, setRutas] = useState([])
  const [cargandoRutas, setCargandoRutas] = useState(true)
  const [busqueda, setBusqueda] = useState('')
  const [idRuta, setIdRuta] = useState('')
  const [fechaDesde, setFechaDesde] = useState(inicioMes)
  const [fechaHasta, setFechaHasta] = useState(hoy)
  const [movimientos, setMovimientos] = useState([])
  const [cargandoMovimientos, setCargandoMovimientos] = useState(false)
  const [filtroTipo, setFiltroTipo] = useState('todos')
  const [error, setError] = useState('')
  const [apartado, setApartado] = useState('rutas')

  const [filaHover, setFilaHover] = useState(null)
  const [objetivo, setObjetivo] = useState(null)
  const [preview, setPreview] = useState(null)
  const [previewDetalle, setPreviewDetalle] = useState([])
  const [previewTablas, setPreviewTablas] = useState([])
  const [selectCopiado, setSelectCopiado] = useState('')
  const [jobId, setJobId] = useState('')
  const [cargandoPreview, setCargandoPreview] = useState(false)
  const [justificacion, setJustificacion] = useState('')
  const [ejecutando, setEjecutando] = useState(false)
  const [resultado, setResultado] = useState(null)
  const [pasos, setPasos] = useState(null)

  useEffect(() => {
    api('/api/auth/sistemas/rutas', { headers })
      .then(setRutas)
      .catch((err) => setError(err.message))
      .finally(() => setCargandoRutas(false))
  }, [session.token])

  const cargarMovimientos = () => {
    if (!idRuta) return
    setCargandoMovimientos(true); setError('')
    api(`/api/auth/sistemas/rutas/${idRuta}/movimientos?fechaDesde=${fechaDesde}&fechaHasta=${fechaHasta}`, { headers })
      .then(setMovimientos)
      .catch((err) => setError(err.message))
      .finally(() => setCargandoMovimientos(false))
  }

  useEffect(() => { cargarMovimientos() }, [idRuta, fechaDesde, fechaHasta])

  const MOVIMIENTOS_POR_PAGINA = 20
  const [pagina, setPagina] = useState(1)
  useEffect(() => { setPagina(1); setFilaHover(null) }, [idRuta, fechaDesde, fechaHasta, filtroTipo])

  const rutasFiltradas = rutas.filter((r) => `${r.ruta} ${r.tecnico}`.toLowerCase().includes(busqueda.trim().toLowerCase()))
  const rutaActual = rutas.find((r) => String(r.idRuta) === String(idRuta))
  const visibles = filtroTipo === 'todos' ? movimientos : movimientos.filter((m) => m.tipo === filtroTipo)
  const totalPaginas = Math.max(1, Math.ceil(visibles.length / MOVIMIENTOS_POR_PAGINA))
  const visiblesPagina = visibles.slice((pagina - 1) * MOVIMIENTOS_POR_PAGINA, pagina * MOVIMIENTOS_POR_PAGINA)

  const abrirObjetivo = (movimiento) => {
    setObjetivo(movimiento); setPreview(null); setPreviewDetalle([]); setPreviewTablas([]); setSelectCopiado(''); setJustificacion(''); setResultado(null); setError('')
    setJobId(crypto.randomUUID())
    setCargandoPreview(true)
    Promise.all([
      api(`/api/auth/sistemas/rutas/${idRuta}/cascada/preview?desdeFecha=${encodeURIComponent(movimiento.fecha)}`, { headers }),
      api(`/api/auth/sistemas/rutas/${idRuta}/cascada/preview-detalle?desdeFecha=${encodeURIComponent(movimiento.fecha)}`, { headers }),
      api(`/api/auth/sistemas/rutas/${idRuta}/cascada/preview-tablas?desdeFecha=${encodeURIComponent(movimiento.fecha)}`, { headers }),
    ])
      .then(([resumen, detalle, tablas]) => { setPreview(resumen); setPreviewDetalle(detalle); setPreviewTablas(tablas) })
      .catch((err) => setError(err.message))
      .finally(() => setCargandoPreview(false))
  }

  const cerrarObjetivo = () => { if (ejecutando) return; setObjetivo(null); setPreview(null); setPreviewDetalle([]); setPreviewTablas([]); setPasos(null) }

  const ejecutar = async () => {
    if (!justificacion.trim()) { setError('Debes indicar una justificación.'); return }
    if (!preview || preview.length === 0) return
    setEjecutando(true); setError('')
    setPasos(preview.map((p) => ({ ...p, estado: 'pendiente' })))

    const controller = new AbortController()
    const esperarConexion = new Promise((resolve) => {
      let resuelto = false
      const listo = () => { if (!resuelto) { resuelto = true; resolve() } }
      escucharCascadaSistemas(session.token, jobId, controller.signal, listo, (evento) => {
        setPasos((actual) => actual?.map((paso) => (
          paso.tipo === evento.tipo && paso.idReferencia === evento.idReferencia
            ? { ...paso, estado: evento.etapa }
            : paso
        )) ?? actual)
      }).catch(() => listo())
      setTimeout(listo, 4000)
    })
    await esperarConexion

    try {
      const data = await api(`/api/auth/sistemas/rutas/${idRuta}/cascada/ejecutar`, {
        method: 'POST', headers,
        body: JSON.stringify({ desdeFecha: objetivo.fecha, justificacion: justificacion.trim(), jobId }),
      })
      setPasos((actual) => actual?.map((paso) => ({ ...paso, estado: 'revertido' })) ?? actual)
      setResultado(data)
      await new Promise((resolve) => setTimeout(resolve, 750))
      setPreview(null); setObjetivo(null); setPasos(null)
      cargarMovimientos()
    } catch (err) {
      setPasos((actual) => actual?.map((paso) => ({ ...paso, estado: 'cancelado' })) ?? actual)
      setError(`Se aplicó ROLLBACK: no se guardó ningún cambio. ${err.message}`)
    } finally { controller.abort(); setEjecutando(false) }
  }

  const previewAgrupado = Object.values(previewDetalle.reduce((acc, item) => {
    const clave = `${item.tipo}-${item.idReferencia}`
    if (!acc[clave]) acc[clave] = { ...item, productos: [] }
    acc[clave].productos.push(item)
    return acc
  }, {}))
  const saldosProyectados = Object.values(previewDetalle.reduce((acc, item) => {
    acc[item.idProducto] = {
      idProducto: item.idProducto,
      producto: item.producto,
      saldoActual: item.saldoActual,
      saldoProyectado: item.saldoProyectadoFinal,
    }
    return acc
  }, {}))
  const bloqueosPreview = [...new Set(previewDetalle.filter((item) => item.bloqueado).map((item) => item.motivoBloqueo))]

  const copiarSelect = async (tabla, consultaSql) => {
    try {
      await navigator.clipboard.writeText(consultaSql)
      setSelectCopiado(tabla)
      setTimeout(() => setSelectCopiado(''), 1800)
    } catch { setError('No se pudo copiar el SELECT. Puedes seleccionarlo manualmente.') }
  }
  const valorTabla = (valor) => valor === null || valor === undefined ? 'NULL' : typeof valor === 'boolean' ? (valor ? '1' : '0') : String(valor)

  return <main className="warehouse-page">
    <header className="topbar">
      <div className="topbar-brand"><BrandMark /><span>Panel de Sistemas</span></div>
      <div className="topbar-user"><div className="avatar">{initials}</div><div><strong>{usuario.nombre}</strong><span>{usuario.sucursal.nombre}</span></div><button type="button" onClick={onLogout}>Cerrar sesión</button></div>
    </header>

    <nav className="sistemas-section-tabs" aria-label="Apartados de Sistemas"><button type="button" className={apartado === 'rutas' ? 'active' : ''} onClick={() => setApartado('rutas')}>Reversión de rutas</button><button type="button" className={apartado === 'passwords' ? 'active' : ''} onClick={() => setApartado('passwords')}>Contraseñas de usuarios</button></nav>

    {apartado === 'passwords' ? <PasswordResetAdminPanel session={session} /> : <section className="sistemas-workbench">
      <aside className="seller-sidebar">
        <div className="seller-sidebar-heading"><p>RUTAS</p><span>{rutas.length}</span></div>
        <div className="seller-search"><span>⌕</span><input type="search" placeholder="Buscar ruta o técnico…" value={busqueda} onChange={(event) => setBusqueda(event.target.value)} /></div>
        <div className="seller-list">
          {cargandoRutas ? <div className="seller-loading">Consultando…</div> : rutasFiltradas.map((ruta) => (
            <button className={Number(idRuta) === ruta.idRuta ? 'active' : ''} type="button" key={ruta.idRuta} onClick={() => setIdRuta(String(ruta.idRuta))}>
              <div><strong>{ruta.ruta}</strong><small><b>{ruta.tecnico}</b>{ruta.idVendedor ? ` · Vendedor #${ruta.idVendedor}` : ''}</small></div>
            </button>
          ))}
        </div>
      </aside>

      <section className="warehouse-orders warehouse-orders--workbench">
        <div className="warehouse-orders-heading">
          <div><p>PANEL DE SISTEMAS</p><h2>{rutaActual ? rutaActual.ruta : 'Selecciona una ruta'}</h2>{rutaActual && <small>Técnico asignado: {rutaActual.tecnico}</small>}</div>
          <span>{visibles.length} movimiento(s)</span>
        </div>

        {idRuta && <>
          <div className="warehouse-order-toolbar">
            <div className="warehouse-order-tabs">
              <button type="button" className={filtroTipo === 'todos' ? 'active' : ''} onClick={() => setFiltroTipo('todos')}>Todo <b>{movimientos.length}</b></button>
              <button type="button" className={filtroTipo === 'CUADRE' ? 'active' : ''} onClick={() => setFiltroTipo('CUADRE')}>Cuadres <b>{movimientos.filter((m) => m.tipo === 'CUADRE').length}</b></button>
              <button type="button" className={filtroTipo === 'CUADRE_PRELIMINAR' ? 'active' : ''} onClick={() => setFiltroTipo('CUADRE_PRELIMINAR')}>Preliminares <b>{movimientos.filter((m) => m.tipo === 'CUADRE_PRELIMINAR').length}</b></button>
              <button type="button" className={filtroTipo === 'PEDIDO' ? 'active' : ''} onClick={() => setFiltroTipo('PEDIDO')}>Pedidos <b>{movimientos.filter((m) => m.tipo === 'PEDIDO').length}</b></button>
            </div>
          </div>
          <div className="warehouse-date-range">
            <label>Desde<input type="date" value={fechaDesde} max={fechaHasta} onChange={(event) => setFechaDesde(event.target.value)} /></label>
            <label>Hasta<input type="date" value={fechaHasta} min={fechaDesde} onChange={(event) => setFechaHasta(event.target.value)} /></label>
            <div className="date-quick-actions">
              <button type="button" className={fechaDesde === inicioHistorico && fechaHasta === hoy ? 'active' : ''} onClick={() => { setFechaDesde(inicioHistorico); setFechaHasta(hoy) }}>Histórico</button>
              <button type="button" className={fechaDesde === inicioMes && fechaHasta === hoy ? 'active' : ''} onClick={() => { setFechaDesde(inicioMes); setFechaHasta(hoy) }}>Este mes</button>
              <button type="button" className={fechaDesde === hoy && fechaHasta === hoy ? 'active' : ''} onClick={() => { setFechaDesde(hoy); setFechaHasta(hoy) }}>Hoy</button>
            </div>
            <div><small>Periodo consultado</small><strong>{fechaDesde === fechaHasta ? fechaDesde : `${fechaDesde} — ${fechaHasta}`}</strong></div>
          </div>
        </>}

        {error && !objetivo && <div className="warehouse-orders-message warehouse-orders-message--error">{error}</div>}
        {resultado && <div className="warehouse-orders-message">Reversión #{resultado.idReversion} completada: se revirtieron {resultado.cantidadMovimientos} movimientos de la ruta.</div>}

        {!idRuta ? <div className="warehouse-orders-message">Selecciona una ruta para ver sus pedidos y cuadres.</div>
          : cargandoMovimientos ? <div className="warehouse-orders-message">Consultando movimientos…</div>
          : visibles.length === 0 ? <div className="warehouse-orders-message">No existen movimientos con estos filtros.</div>
          : <div className="warehouse-pending-list sistemas-pending-list" onMouseLeave={() => setFilaHover(null)}>
            {visiblesPagina.map((m, idx) => (
              <article
                className={`warehouse-pending-order sistemas-order-row ${filaHover !== null && idx <= filaHover ? 'sistemas-row-en-rango' : ''} ${filaHover === idx ? 'sistemas-row-objetivo' : ''}`}
                key={`${m.tipo}-${m.idReferencia}`}
                onMouseEnter={() => setFilaHover(idx)}
                onClick={() => abrirObjetivo(m)}
              >
                <div className="warehouse-order-id"><span>{ETIQUETAS_TIPO_CORTAS[m.tipo] || m.tipo}</span><strong>#{m.idReferencia}</strong></div>
                <div className="warehouse-order-date"><small>{ETIQUETAS_TIPO_MOVIMIENTO[m.tipo] || m.tipo}</small><strong>{dateTime.format(new Date(m.fecha))}</strong><span>{m.observacion || 'Sin observación'}</span></div>
                <dl><div><dt>Tipo</dt><dd>{ETIQUETAS_TIPO_MOVIMIENTO[m.tipo] || m.tipo}</dd></div><div><dt>Total</dt><dd>{money.format(m.total || 0)}</dd></div><div><dt>Estado</dt><dd>{m.estado}</dd></div></dl>
                {filaHover !== null && idx <= filaHover
                  ? <span className="order-status order-status--revert">Se revertirá</span>
                  : <span className={`order-status order-status--${m.estado === 'PENDIENTE' ? 'pending' : 'approved'}`}>{m.estado}</span>}
                <div className="warehouse-order-actions">
                  <button type="button" onClick={(event) => { event.stopPropagation(); abrirObjetivo(m) }}>Revertir desde aquí…</button>
                </div>
              </article>
            ))}
          </div>}
        {idRuta && visibles.length > 0 && totalPaginas > 1 && (
          <div className="sistemas-paginacion">
            <button type="button" disabled={pagina === 1} onClick={() => setPagina((p) => Math.max(1, p - 1))}>← Anterior</button>
            <span>Página {pagina} de {totalPaginas} · {visibles.length} movimiento(s)</span>
            <button type="button" disabled={pagina === totalPaginas} onClick={() => setPagina((p) => Math.min(totalPaginas, p + 1))}>Siguiente →</button>
          </div>
        )}
      </section>
    </section>}

    {objetivo && <div className="order-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !ejecutando) cerrarObjetivo() }}>
      <section className="accounting-dialog accounting-detail-dialog sistemas-restore-dialog">
        <header>
          <div><p>REVERSIÓN EN CASCADA</p><h2>{rutaActual?.ruta}</h2><span>Desde {ETIQUETAS_TIPO_MOVIMIENTO[objetivo.tipo] || objetivo.tipo} #{objetivo.idReferencia} ({dateTime.format(new Date(objetivo.fecha))}) hasta ahora</span></div>
          <button type="button" disabled={ejecutando} onClick={cerrarObjetivo}>×</button>
        </header>

        {pasos ? <>
          <div className="cascada-progress-list">
            {pasos.map((p) => (
              <div className={`cascada-progress-row cascada-progress-row--${p.estado}`} key={`${p.tipo}-${p.idReferencia}`}>
                <span className="cascada-progress-icon">
                  {p.estado === 'revertido' ? '✓' : p.estado === 'procesando' ? <i className="cascada-spinner" /> : p.estado === 'cancelado' ? '!' : ''}
                </span>
                <div><strong>{ETIQUETAS_TIPO_MOVIMIENTO[p.tipo] || p.tipo} #{p.idReferencia}</strong><small>{dateTime.format(new Date(p.fecha))}</small></div>
                <span className="cascada-progress-estado">{p.estado === 'revertido' ? 'Revertido' : p.estado === 'procesando' ? 'Revirtiendo…' : p.estado === 'cancelado' ? 'Sin cambios (rollback)' : 'En espera'}</span>
              </div>
            ))}
          </div>
          {resultado
            ? <div className="accounting-edit-notice cascada-progress-done"><strong>Reversión #{resultado.idReversion} completada</strong><span>Se revirtieron {resultado.cantidadMovimientos} movimientos de la ruta.</span></div>
            : error ? <div className="accounting-edit-notice cascada-progress-rollback"><strong>Rollback completado</strong><span>La operación fue cancelada y todos los datos regresaron a su estado original.</span></div>
            : <div className="accounting-edit-notice"><strong>Revirtiendo movimientos…</strong><span>No cierres esta ventana hasta que termine.</span></div>}
          {error && <div className="accounting-message error">{error}</div>}
        </> : <>
          {cargandoPreview ? <div className="accounting-message">Calculando qué se revertiría…</div>
            : !preview ? null
            : preview.length === 0 ? <div className="accounting-message">No hay movimientos que revertir desde ese punto.</div>
            : <>
              <div className="accounting-edit-notice"><strong>Se revertirán {preview.length} movimientos</strong><span>Todo lo posterior a este punto en esta ruta se anula también, para no dejar nada a medias.</span></div>
              <div className="accounting-table-scroll"><table><thead><tr><th>Tipo</th><th>Id</th><th>Fecha</th><th>Total</th></tr></thead><tbody>
                {preview.map((p) => <tr key={`${p.tipo}-${p.idReferencia}`}><td>{ETIQUETAS_TIPO_MOVIMIENTO[p.tipo] || p.tipo}</td><td>#{p.idReferencia}</td><td>{dateTime.format(new Date(p.fecha))}</td><td>{money.format(p.total || 0)}</td></tr>)}
              </tbody></table></div>

              {bloqueosPreview.length > 0 && <div className="sistemas-preview-blocked"><strong>La restauraci&oacute;n est&aacute; bloqueada</strong>{bloqueosPreview.map((mensaje) => <span key={mensaje}>{mensaje}</span>)}</div>}

              <section className="sistemas-preview-section">
                <div className="sistemas-preview-heading"><div><small>RESULTADO PROYECTADO</small><h3>As&iacute; quedar&aacute; el saldo de la ruta</h3></div><span>{saldosProyectados.length} producto(s)</span></div>
                <div className="accounting-table-scroll"><table><thead><tr><th>Producto</th><th>Ahora</th><th>Despu&eacute;s</th><th>Cambio</th></tr></thead><tbody>
                  {saldosProyectados.map((item) => { const diferencia = Number(item.saldoProyectado || 0) - Number(item.saldoActual || 0); return <tr key={item.idProducto}><td><strong>{item.producto}</strong><small>Producto #{item.idProducto}</small></td><td>{integer.format(item.saldoActual || 0)}</td><td><strong>{integer.format(item.saldoProyectado || 0)}</strong></td><td className={diferencia >= 0 ? 'sistemas-delta-up' : 'sistemas-delta-down'}>{diferencia >= 0 ? '+' : ''}{integer.format(diferencia)}</td></tr> })}
                </tbody></table></div>
              </section>

              <section className="sistemas-preview-section">
                <div className="sistemas-preview-heading"><div><small>TRAZABILIDAD</small><h3>Detalle de pedidos, cuadres y tablas</h3></div><span>{previewAgrupado.length} movimiento(s)</span></div>
                <div className="sistemas-preview-movimientos">
                  {previewAgrupado.map((movimiento) => <details key={`${movimiento.tipo}-${movimiento.idReferencia}`} open={movimiento.tipo === objetivo.tipo && movimiento.idReferencia === objetivo.idReferencia}>
                    <summary><div><strong>{ETIQUETAS_TIPO_MOVIMIENTO[movimiento.tipo] || movimiento.tipo} #{movimiento.idReferencia}</strong><small>{dateTime.format(new Date(movimiento.fecha))}</small></div><span>{movimiento.estadoActual} &rarr; {movimiento.estadoProyectado}</span></summary>
                    <div className="sistemas-preview-meta"><span><b>Observaci&oacute;n:</b> {movimiento.observacion || 'Sin observaci&oacute;n'}</span><span><b>Tabla principal:</b> {movimiento.tablaPrincipal}</span><span><b>Tablas involucradas:</b> {movimiento.tablasAfectadas}</span></div>
                    <div className="accounting-table-scroll"><table><thead><tr><th>Producto</th><th>Movimiento</th><th>Saldo antes</th><th>Saldo despu&eacute;s</th><th>IMEIs</th></tr></thead><tbody>
                      {movimiento.productos.map((producto) => <tr key={`${movimiento.tipo}-${movimiento.idReferencia}-${producto.idProducto}`}><td><strong>{producto.producto}</strong><small>#{producto.idProducto}</small>{producto.codigos && <small className="sistemas-preview-codigos" title={producto.codigos}>{producto.codigos}</small>}</td><td>{integer.format(producto.cantidadMovimiento || 0)}</td><td>{integer.format(producto.saldoAntesMovimiento || 0)}</td><td>{integer.format(producto.saldoDespuesMovimiento || 0)}</td><td>{integer.format(producto.fisicosAfectados || 0)}{producto.fisicosVendidos > 0 ? ` (${producto.fisicosVendidos} vendidos)` : ''}</td></tr>)}
                    </tbody></table></div>
                  </details>)}
                </div>
              </section>

              <section className="sistemas-preview-section sistemas-sql-preview">
                <div className="sistemas-preview-heading"><div><small>VISTA DE BASE DE DATOS</small><h3>Resultado actual y resultado despu&eacute;s del rollback</h3></div><span>{previewTablas.length} consulta(s)</span></div>
                <p className="sistemas-sql-help">Cada bloque representa el resultado del SELECT sobre la tabla real. Las celdas amarillas son valores que cambiar&aacute;n.</p>
                <div className="sistemas-sql-tables">
                  {previewTablas.map((tabla, tablaIndex) => {
                    const claveTabla = `${tabla.tipoMovimiento}-${tabla.idReferencia}-${tabla.tabla}-${tablaIndex}`
                    return <details key={claveTabla} open={tabla.tabla === 'tbl_Caja' || tabla.tabla === 'tbl_Cuadre'}>
                      <summary><div><strong>{tabla.tabla}</strong><small>{ETIQUETAS_TIPO_MOVIMIENTO[tabla.tipoMovimiento] || tabla.tipoMovimiento} #{tabla.idReferencia}</small></div><span>{tabla.filasActuales.length} fila(s)</span></summary>
                      <div className="sistemas-sql-query"><code>{tabla.consultaSql}</code><button type="button" onClick={() => copiarSelect(claveTabla, tabla.consultaSql)}>{selectCopiado === claveTabla ? 'Copiado' : 'Copiar SELECT'}</button></div>
                      <div className="sistemas-sql-results">
                        {[['AHORA', tabla.filasActuales], ['DESPUÉS DEL ROLLBACK', tabla.filasProyectadas]].map(([titulo, filas], lado) => <section key={titulo}>
                          <header><strong>{titulo}</strong><span>{filas.length} fila(s)</span></header>
                          {filas.length === 0 ? <div className="sistemas-sql-empty">(0 filas afectadas)</div> : <div className="sistemas-sql-grid"><table><thead><tr>{tabla.columnas.map((columna) => <th key={columna}>{columna}</th>)}</tr></thead><tbody>{filas.map((fila, filaIndex) => <tr key={filaIndex}>{tabla.columnas.map((columna) => { const cambio = lado === 1 && valorTabla(tabla.filasActuales[filaIndex]?.[columna]) !== valorTabla(fila[columna]); return <td className={cambio ? 'changed' : ''} key={columna} title={valorTabla(fila[columna])}>{valorTabla(fila[columna])}</td> })}</tr>)}</tbody></table></div>}
                          <footer>{filas.length} row(s) affected</footer>
                        </section>)}
                      </div>
                    </details>
                  })}
                  <details open>
                    <summary><div><strong>tbl_Sistemas_ReversionRuta</strong><small>Auditor&iacute;a del rollback</small></div><span>1 fila proyectada</span></summary>
                    <div className="sistemas-sql-query"><code>{`SELECT * FROM dbo.tbl_Sistemas_ReversionRuta WHERE JobId = '${jobId}';`}</code><button type="button" onClick={() => copiarSelect('auditoria', `SELECT * FROM dbo.tbl_Sistemas_ReversionRuta WHERE JobId = '${jobId}';`)}>{selectCopiado === 'auditoria' ? 'Copiado' : 'Copiar SELECT'}</button></div>
                    <div className="sistemas-sql-results"><section><header><strong>AHORA</strong><span>0 fila(s)</span></header><div className="sistemas-sql-empty">(0 filas afectadas)</div><footer>0 row(s) affected</footer></section><section><header><strong>DESPU&Eacute;S DEL ROLLBACK</strong><span>1 fila</span></header><div className="sistemas-sql-grid"><table><thead><tr>{['Id_Ruta','DesdeFecha','Id_UsuarioSistemas','NombreUsuarioSistemas','Justificacion','CantidadMovimientos','JobId','Fecha_Registro'].map((columna) => <th key={columna}>{columna}</th>)}</tr></thead><tbody><tr>{[idRuta,objetivo.fecha,usuario.id,usuario.nombre,justificacion || '(motivo pendiente de escribir)',preview.length,jobId,'Fecha y hora del servidor'].map((valor, index) => <td className="changed" key={index}>{valorTabla(valor)}</td>)}</tr></tbody></table></div><footer>1 row(s) affected</footer></section></div>
                  </details>
                </div>
              </section>
            </>}

          {error && <div className="accounting-message error">{error}</div>}

          <div className="accounting-form-grid">
            <label>Justificación<textarea rows="3" maxLength="500" value={justificacion} onChange={(e) => setJustificacion(e.target.value)} placeholder="Explica por qué se revierte (obligatorio)" /></label>
          </div>

          <footer>
            <button type="button" disabled={ejecutando} onClick={cerrarObjetivo}>Cancelar</button>
            <button className="primary" type="button" disabled={ejecutando || cargandoPreview || !preview || preview.length === 0 || !justificacion.trim() || bloqueosPreview.length > 0} onClick={ejecutar}>{ejecutando ? 'Restaurando…' : bloqueosPreview.length > 0 ? 'Restauración bloqueada' : `Restaurar ${preview?.length || 0} movimientos`}</button>
          </footer>
        </>}
      </section>
    </div>}
  </main>
}

function ModuloNoDisponibleEnMovil({ usuario, onLogout }) {
  const modulo = usuario.rol?.toLowerCase() === 'sistemas' ? 'Sistemas' : 'Contabilidad'
  return <main className="mobile-module-blocked">
    <div className="mobile-module-blocked__backdrop" aria-hidden="true"><span /><span /><span /></div>
    <section className="mobile-module-blocked__dialog" role="dialog" aria-modal="true" aria-labelledby="mobile-module-title">
      <div className="mobile-module-blocked__mark"><BrandMark /></div>
      <p>ACCESO DESDE DISPOSITIVO MÓVIL</p>
      <h1 id="mobile-module-title">Este apartado no está disponible aquí</h1>
      <span>El módulo de <strong>{modulo}</strong> no soporta teléfonos ni tablets. Ingresa desde una computadora para utilizar todas sus funciones de forma segura.</span>
      <div className="mobile-module-blocked__device"><b>PC</b><div><strong>Acceso requerido</strong><small>Computadora de escritorio o portátil</small></div></div>
      <button type="button" onClick={onLogout}>Cerrar sesión</button>
      <small>Tu cuenta no presenta ningún problema.</small>
    </section>
  </main>
}

function Application() {
  const [sucursales, setSucursales] = useState([])
  const [usuario, setUsuario] = useState('')
  const [password, setPassword] = useState('')
  const [idSucursal, setIdSucursal] = useState('')
  const [mostrarPassword, setMostrarPassword] = useState(false)
  const [cargandoSucursales, setCargandoSucursales] = useState(true)
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState('')
  const [session, setSession] = useState(null)
  const [passwordGate, setPasswordGate] = useState('checking')
  const [passwordGateError, setPasswordGateError] = useState('')
  const [nuevaPassword, setNuevaPassword] = useState('')
  const [confirmarPassword, setConfirmarPassword] = useState('')
  const [mostrarNuevaPassword, setMostrarNuevaPassword] = useState(false)
  const [mostrarConfirmarPassword, setMostrarConfirmarPassword] = useState(false)
  const [cambiandoPassword, setCambiandoPassword] = useState(false)
  const [saldo, setSaldo] = useState(null)
  const [cargandoSaldo, setCargandoSaldo] = useState(false)
  const [saldoError, setSaldoError] = useState('')
  const [mostrarLoginModal, setMostrarLoginModal] = useState(false)
  const [dispositivoMovil, setDispositivoMovil] = useState(() => detectarDispositivoMovil())

  useEffect(() => {
    const actualizarDispositivo = () => setDispositivoMovil(detectarDispositivoMovil())
    window.addEventListener('resize', actualizarDispositivo)
    window.addEventListener('orientationchange', actualizarDispositivo)
    return () => {
      window.removeEventListener('resize', actualizarDispositivo)
      window.removeEventListener('orientationchange', actualizarDispositivo)
    }
  }, [])

  useEffect(() => {
    api('/api/auth/sucursales')
      .then((data) => {
        setSucursales(data)
        const santaCruz = data.find((sucursal) => sucursal.nombre?.trim().toUpperCase() === 'SANTA CRUZ')
        if (santaCruz) setIdSucursal(String(santaCruz.id))
      })
      .catch((err) => setError(err.message))
      .finally(() => setCargandoSucursales(false))
    const saved = sessionStorage.getItem(SESSION_KEY)
    if (!saved) return
    try {
      const parsed = JSON.parse(saved)
      api('/api/auth/me', { headers: { Authorization: `Bearer ${parsed.token}` } })
        .then((currentUser) => setSession({ ...parsed, usuario: currentUser }))
        .catch(() => sessionStorage.removeItem(SESSION_KEY))
    } catch { sessionStorage.removeItem(SESSION_KEY) }
  }, [])

  const token = useMemo(() => session?.token, [session])
  useEffect(() => {
    if (!token) return
    let active = true
    const revisar = () => {
      api('/api/auth/password/estado', { headers: { Authorization: `Bearer ${token}` } })
        .then((data) => { if (active) { setPasswordGate(data.pendiente ? 'pending' : 'clear'); setPasswordGateError('') } })
        .catch((err) => { if (active) { setPasswordGate('error'); setPasswordGateError(err.message) } })
    }
    setPasswordGate('checking')
    revisar()
    const interval = window.setInterval(revisar, 30000)
    return () => { active = false; window.clearInterval(interval) }
  }, [token])
  useEffect(() => {
    if (!token || session?.usuario?.rol?.toLowerCase() !== 'tecnico' || !session?.usuario?.tecnico?.esTecnico || !session.usuario.tecnico.idRuta) return
    let active = true
    queueMicrotask(() => {
      if (!active) return
      setCargandoSaldo(true)
      setSaldoError('')
      api('/api/auth/saldo-ruta', { headers: { Authorization: `Bearer ${token}` } })
        .then((data) => { if (active) setSaldo(data) })
        .catch((err) => { if (active) setSaldoError(err.message) })
        .finally(() => { if (active) setCargandoSaldo(false) })
    })
    return () => { active = false }
  }, [token, session?.usuario?.rol, session?.usuario?.tecnico?.esTecnico, session?.usuario?.tecnico?.idRuta])

  async function handleSubmit(event) {
    event.preventDefault()
    setError('')
    if (!usuario.trim() || !password || !idSucursal) { setError('Completa usuario, contraseña y sucursal.'); return }
    setEnviando(true)
    try {
      const data = await api('/api/auth/login', { method: 'POST', body: JSON.stringify({ usuario: usuario.trim(), password, idSucursal: Number(idSucursal) }) })
      sessionStorage.setItem(SESSION_KEY, JSON.stringify(data))
      setSession(data)
      setPassword('')
    } catch (err) { setError(err.message) } finally { setEnviando(false) }
  }

  async function handleLogout() {
    const currentToken = session?.token
    setSession(null); setSaldo(null); setPasswordGate('checking'); sessionStorage.removeItem(SESSION_KEY)
    if (currentToken) await api('/api/auth/logout', { method: 'POST', headers: { Authorization: `Bearer ${currentToken}` } }).catch(() => null)
  }

  const rolActual = session?.usuario?.rol?.toLowerCase()
  async function handleCambioPassword(event) {
    event.preventDefault()
    setPasswordGateError('')
    if (nuevaPassword.length < 8 || nuevaPassword.length > 72 || nuevaPassword !== confirmarPassword) {
      setPasswordGateError('Usa entre 8 y 72 caracteres y confirma la misma contraseña.'); return
    }
    setCambiandoPassword(true)
    try {
      await api('/api/auth/password/cambiar', {
        method: 'POST', headers: { Authorization: `Bearer ${token}` },
        body: JSON.stringify({ nuevaPassword, confirmarPassword }),
      })
      setNuevaPassword(''); setConfirmarPassword(''); setPasswordGate('clear')
    } catch (err) { setPasswordGateError(err.message) } finally { setCambiandoPassword(false) }
  }
  if (session && passwordGate !== 'clear') {
    return <main className="password-gate-page"><section className="password-gate-card" role="dialog" aria-modal="true" aria-labelledby="password-gate-title">
      <div className="password-gate-mark"><BrandMark /></div>
      {passwordGate === 'pending' ? <>
        <p className="password-gate-kicker">SEGURIDAD DE LA CUENTA</p>
        <h1 id="password-gate-title">Cambia tu contraseña</h1>
        <p>Sistemas solicitó renovar la contraseña de <strong>{session.usuario.nombre}</strong>. Para continuar, crea una nueva.</p>
        <form onSubmit={handleCambioPassword}>
          <label>Nueva contraseña<div className="password-gate-input"><input autoComplete="new-password" type={mostrarNuevaPassword ? 'text' : 'password'} minLength={8} maxLength={72} value={nuevaPassword} onChange={(event) => setNuevaPassword(event.target.value)} required /><button className="password-gate-eye" type="button" aria-label={mostrarNuevaPassword ? 'Ocultar nueva contraseña' : 'Mostrar nueva contraseña'} aria-pressed={mostrarNuevaPassword} onClick={() => setMostrarNuevaPassword((actual) => !actual)}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z" /><circle cx="12" cy="12" r="3" />{!mostrarNuevaPassword && <path d="M4 20 20 4" />}</svg></button></div></label>
          <label>Confirmar contraseña<div className="password-gate-input"><input autoComplete="new-password" type={mostrarConfirmarPassword ? 'text' : 'password'} minLength={8} maxLength={72} value={confirmarPassword} onChange={(event) => setConfirmarPassword(event.target.value)} required /><button className="password-gate-eye" type="button" aria-label={mostrarConfirmarPassword ? 'Ocultar confirmación' : 'Mostrar confirmación'} aria-pressed={mostrarConfirmarPassword} onClick={() => setMostrarConfirmarPassword((actual) => !actual)}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z" /><circle cx="12" cy="12" r="3" />{!mostrarConfirmarPassword && <path d="M4 20 20 4" />}</svg></button></div></label>
          {passwordGateError && <div className="password-gate-error">{passwordGateError}</div>}
          <button type="submit" disabled={cambiandoPassword}>{cambiandoPassword ? 'Guardando…' : 'Guardar y continuar'}</button>
        </form>
      </> : <><h1 id="password-gate-title">Verificando tu cuenta</h1><p>{passwordGate === 'error' ? passwordGateError : 'Comprobando si tienes un cambio de contraseña pendiente…'}</p>{passwordGate === 'error' && <button type="button" onClick={() => { setPasswordGate('checking'); api('/api/auth/password/estado', { headers: { Authorization: `Bearer ${token}` } }).then((data) => { setPasswordGate(data.pendiente ? 'pending' : 'clear'); setPasswordGateError('') }).catch((err) => { setPasswordGate('error'); setPasswordGateError(err.message) }) }}>Reintentar</button>}</>}
      <button type="button" className="password-gate-logout" onClick={handleLogout}>Cerrar sesión</button>
    </section></main>
  }
  if (session && dispositivoMovil && (rolActual === 'contabilidad' || rolActual === 'sistemas')) {
    return <ModuloNoDisponibleEnMovil usuario={session.usuario} onLogout={handleLogout} />
  }
  if (rolActual === 'almacenero') {
    return <WarehouseDashboard session={session} onLogout={handleLogout} />
  }
  if (rolActual === 'contabilidad') {
    return <AccountingDashboard session={session} onLogout={handleLogout} />
  }
  if (rolActual === 'sistemas') {
    return <SystemsDashboard session={session} onLogout={handleLogout} />
  }
  if (session) return <Dashboard session={session} saldo={saldo} cargandoSaldo={cargandoSaldo} saldoError={saldoError} onLogout={handleLogout} />

  const loginFieldProps = {
    usuario, setUsuario, password, setPassword, mostrarPassword, setMostrarPassword,
    idSucursal, setIdSucursal, sucursales, cargandoSucursales, error, enviando, onSubmit: handleSubmit,
  }

  return (
    <>
      <main className="landing-page">
        <nav className="landing-nav">
          <div className="brand brand--light"><BrandMark /><span>Acceso General</span></div>
          <button type="button" className="landing-login-button" onClick={() => setMostrarLoginModal(true)}>Iniciar sesión</button>
        </nav>

        <section className="landing-hero">
          <span className="login-kicker">SISTEMA INTERNO</span>
          <h1>Control operativo<br />en un solo lugar.</h1>
          <p>Accede de forma segura a la información de tu sucursal, ruta e inventario asignado.</p>
          <button type="button" className="landing-hero-cta" onClick={() => setMostrarLoginModal(true)}>Iniciar sesión <b>→</b></button>
          <div className="login-capabilities landing-capabilities" aria-label="Módulos disponibles">
            <span><b>S</b>Sucursales<small>Multi-sede en tiempo real</small></span>
            <span><b>R</b>Rutas<small>Seguimiento por técnico</small></span>
            <span><b>I</b>Inventario<small>Control físico y saldos</small></span>
          </div>
        </section>

        <section className="landing-section landing-section--light">
          <p className="eyebrow">CÓMO FUNCIONA</p>
          <h2>Onboarding simple,<br />resultados claros.</h2>
          <p className="landing-section-lead">Acceso General centraliza la operación de sucursales, técnicos y almacén: desde el pedido en ruta hasta el cuadre de caja, todo en un mismo sistema.</p>
          <div className="landing-columns">
            <div><strong>Pedidos en tiempo real</strong><span>El técnico arma su pedido desde la ruta y almacén lo aprueba al instante, sin llamadas ni papeleo.</span></div>
            <div><strong>Cuadre de caja controlado</strong><span>Cada IMEI se valida antes de cerrar caja, evitando descuadres y pérdidas de inventario.</span></div>
            <div><strong>Trazabilidad completa</strong><span>Cada producto se rastrea desde que sale de almacén hasta que llega a la ruta y se vende.</span></div>
          </div>
        </section>

        <section className="landing-section">
          <p className="eyebrow">MÓDULOS DEL SISTEMA</p>
          <h2>Todo lo que tu operación necesita.</h2>
          <ul className="landing-module-list">
            <li>Pedidos en Ruta</li>
            <li>Cuadre de Caja</li>
            <li>Control de Inventario</li>
            <li>Depósitos y Contabilidad</li>
            <li>Estadísticas y Reportes</li>
            <li>Vinculación de Escáner QR</li>
          </ul>
          <div className="landing-tags">
            <span>Multi-sucursal</span><span>Roles por usuario</span><span>Historial de cuadres</span>
            <span>Alertas en tiempo real</span><span>Saldo por ruta</span><span>Reportes exportables</span>
          </div>
        </section>

        <section className="landing-section landing-cta">
          <h2>Ingresa para continuar</h2>
          <p>Usa tu usuario, contraseña y sucursal asignada.</p>
          <button type="button" className="landing-hero-cta" onClick={() => setMostrarLoginModal(true)}>Iniciar sesión <b>→</b></button>
        </section>

        <footer className="landing-footer">
          <div className="brand brand--light"><BrandMark /><span>Acceso General</span></div>
          <small>Uso exclusivo para personal autorizado. Las operaciones realizadas quedan asociadas al usuario de la sesión.</small>
        </footer>
      </main>

      <main className="login-page">
        <section className="login-layout">
          <aside className="login-intro">
            <div className="brand brand--light"><BrandMark /><span>Acceso General</span></div>
            <div className="login-intro-content">
              <span className="login-kicker">SISTEMA INTERNO</span>
              <h1>Gesti&oacute;n operativa</h1>
              <p>Acceso centralizado a la informaci&oacute;n operativa de sucursales, rutas, pedidos e inventario.</p>
              <div className="login-capabilities" aria-label="Módulos disponibles">
                <span><b>S</b>Sucursales<small>Multi-sede en tiempo real</small></span>
                <span><b>R</b>Rutas<small>Seguimiento por técnico</small></span>
                <span><b>I</b>Inventario<small>Control físico y saldos</small></span>
              </div>
              <div className="internal-access-notice"><span>i</span><div><strong>Uso exclusivo para personal autorizado</strong><small>Las operaciones realizadas quedan asociadas al usuario de la sesi&oacute;n.</small></div></div>
            </div>
            <span className="service-line"><i /> Servicios disponibles</span>
          </aside>
          <section className="login-card">
            <LoginFormFields idPrefix="classic" {...loginFieldProps} />
          </section>
        </section>
      </main>

      {mostrarLoginModal && (
        <div className="login-modal-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setMostrarLoginModal(false) }}>
          <div className="login-modal-card login-card" role="dialog" aria-modal="true" aria-label="Iniciar sesión">
            <button type="button" className="login-modal-close" aria-label="Cerrar" onClick={() => setMostrarLoginModal(false)}>×</button>
            <LoginFormFields idPrefix="modal" {...loginFieldProps} />
          </div>
        </div>
      )}
    </>
  )
}

function App() {
  const scannerMatch = window.location.pathname.match(/^\/scanner\/([a-zA-Z0-9]+)\/?$/)
  return scannerMatch ? <PhoneScanner token={scannerMatch[1]} /> : <Application />
}

export default App
