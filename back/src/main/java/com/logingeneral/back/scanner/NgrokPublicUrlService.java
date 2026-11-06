package com.logingeneral.back.scanner;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class NgrokPublicUrlService {

    private static final Pattern PUBLIC_HTTPS_URL = Pattern.compile(
            "\\\"public_url\\\"\\s*:\\s*\\\"(https://[^\\\"]+)\\\"");

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(2))
            .build();
    private final URI apiUri;

    public NgrokPublicUrlService(
            @Value("${app.ngrok.api-url:http://127.0.0.1:4040/api/tunnels}") String apiUrl) {
        this.apiUri = URI.create(apiUrl);
    }

    public Optional<String> obtenerUrlPublica() {
        try {
            HttpRequest request = HttpRequest.newBuilder(apiUri)
                    .timeout(Duration.ofSeconds(3))
                    .GET()
                    .build();
            HttpResponse<String> response = httpClient.send(
                    request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() != 200) {
                return Optional.empty();
            }
            Matcher matcher = PUBLIC_HTTPS_URL.matcher(response.body());
            return matcher.find() ? Optional.of(matcher.group(1)) : Optional.empty();
        } catch (Exception ex) {
            return Optional.empty();
        }
    }
}
