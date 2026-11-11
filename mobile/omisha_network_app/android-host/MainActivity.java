package com.omisha.omisha_network_app;

import android.content.Intent;
import android.os.CancellationSignal;

import androidx.annotation.NonNull;
import androidx.credentials.ClearCredentialStateRequest;
import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.ClearCredentialException;
import androidx.credentials.exceptions.GetCredentialException;

import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;

import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.omisha.network_os/google_identity";
    private CredentialManager credentialManager;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        credentialManager = CredentialManager.create(this);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler(this::handleIdentityCall);
    }

    private void handleIdentityCall(MethodCall call, MethodChannel.Result result) {
        if ("googleIdToken".equals(call.method)) {
            String clientId = call.argument("serverClientId");
            String nonce = call.argument("nonce");
            if (clientId == null || clientId.isBlank() || nonce == null || nonce.length() < 32 || nonce.length() > 256) {
                result.error("invalid_request", "Google sign-in configuration is invalid.", null);
                return;
            }
            requestGoogleCredential(clientId, nonce, result);
            return;
        }
        if ("shareInvitation".equals(call.method)) {
            String text = call.argument("text");
            if (text == null || text.isBlank() || text.length() > 2000) {
                result.error("invalid_request", "Invitation text is invalid.", null);
                return;
            }
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType("text/plain");
            send.putExtra(Intent.EXTRA_TEXT, text);
            startActivity(Intent.createChooser(send, "Share OMISHA invitation"));
            result.success(null);
            return;
        }
        if ("clearCredentialState".equals(call.method)) {
            credentialManager.clearCredentialStateAsync(
                    new ClearCredentialStateRequest(),
                    new CancellationSignal(),
                    getMainExecutor(),
                    new androidx.credentials.CredentialManagerCallback<Void, ClearCredentialException>() {
                        @Override
                        public void onResult(Void ignored) {
                            result.success(null);
                        }

                        @Override
                        public void onError(@NonNull ClearCredentialException error) {
                            result.error("sign_out_failed", "Could not clear Google credential state.", null);
                        }
                    });
            return;
        }
        result.notImplemented();
    }

    private void requestGoogleCredential(String clientId, String nonce, MethodChannel.Result result) {
        GetSignInWithGoogleOption googleOption = new GetSignInWithGoogleOption.Builder(clientId)
                .setNonce(nonce)
                .build();
        GetCredentialRequest request = new GetCredentialRequest.Builder()
                .addCredentialOption(googleOption)
                .build();

        AtomicBoolean completed = new AtomicBoolean(false);
        credentialManager.getCredentialAsync(
                this,
                request,
                new CancellationSignal(),
                getMainExecutor(),
                new androidx.credentials.CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                    @Override
                    public void onResult(GetCredentialResponse response) {
                        if (!completed.compareAndSet(false, true)) return;
                        Credential credential = response.getCredential();
                        if (!(credential instanceof CustomCredential)
                                || !GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(credential.getType())) {
                            result.error("unexpected_credential", "Google did not return a supported sign-in credential.", null);
                            return;
                        }
                        try {
                            GoogleIdTokenCredential token = GoogleIdTokenCredential.createFrom(credential.getData());
                            result.success(token.getIdToken());
                        } catch (Exception error) {
                            result.error("invalid_credential", "Google returned an invalid sign-in credential.", null);
                        }
                    }

                    @Override
                    public void onError(@NonNull GetCredentialException error) {
                        if (!completed.compareAndSet(false, true)) return;
                        result.error("google_sign_in_failed", "Google sign-in could not be completed.", null);
                    }
                });
    }
}
