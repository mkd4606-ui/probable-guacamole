# Dockerfile — Railway (ya koi bhi Docker-based hosting) isko dekh kar
# khud-ba-khud build + deploy kar leta hai, koi extra config nahi chahiye.
#
# NOTE: jaan-bujh kar poora build "dart:stable" image ke andar hi rakha
# hai (multi-stage "FROM scratch" nahi kiya) — scratch image mein AOT
# binary ke liye zaroori system libraries (libc waghera) khud copy karni
# padti hain, jo galat hone par silently fail ho sakta hai aur is
# sandbox mein maine isko test nahi kar saka (Dart SDK hi download nahi
# ho saka — README mein pehle bhi likha hai). Poore dart:stable image
# mein chalana thoda bada image size deta hai, lekin reliably kaam
# karega — correctness ko size se zyada priority di.

# Reproducible build ke liye Dart version pin kar sakte hain:
#   docker build --build-arg DART_VERSION=3.5 .
# (default `stable` hai kyunki exact tag is sandbox mein verify nahi ho saka.)
# NOTE: container jaan-bujh kar root se chalta hai — Railway Volume (/data)
# runtime par root-owned mount hota hai, non-root user wahan likh nahi sakta.
ARG DART_VERSION=stable
FROM dart:${DART_VERSION}
WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub get --offline

# Data directory jahan Persistence apni state.json save karegi. Railway
# par isi path (/data) ko ek Volume se mount karna zaroori hai — warna
# yeh sirf container ke andar ka normal folder hoga aur restart par
# delete ho jaayega (HOW_TO_CONNECT.md mein detail hai).
RUN mkdir -p /data
ENV DATA_DIR=/data

# Railway khud PORT environment variable set karta hai — bin/server.dart
# isko already read karta hai (`Platform.environment['PORT']`).
EXPOSE 8080
CMD ["dart", "run", "bin/server.dart"]
