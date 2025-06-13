# FROM node:20-buster AS installer
# COPY . /juice-shop
# WORKDIR /juice-shop
# RUN npm i -g typescript ts-node
# RUN npm install --unsafe-perm
# RUN npm dedupe
# # RUN rm -rf frontend/node_modules
# # RUN rm -rf frontend/.angular
# # RUN rm -rf frontend/src/assets
# RUN mkdir logs
# RUN chown -R 65532 logs
# RUN chgrp -R 0 ftp/ frontend/dist/ logs/ data/ i18n/
# RUN chmod -R g=u ftp/ frontend/dist/ logs/ data/ i18n/
# RUN rm data/chatbot/botDefaultTrainingData.json || true
# RUN rm ftp/legal.md || true
# RUN rm i18n/*.json || true

# ARG CYCLONEDX_NPM_VERSION=latest
# RUN npm install -g @cyclonedx/cyclonedx-npm@$CYCLONEDX_NPM_VERSION
# RUN npm run sbom

# # workaround for libxmljs startup error
# FROM node:20-buster AS libxmljs-builder
# WORKDIR /juice-shop
# RUN apt-get update && apt-get install -y build-essential python3
# COPY --from=installer /juice-shop/node_modules ./node_modules
# RUN rm -rf node_modules/libxmljs/build && \
#   cd node_modules/libxmljs && \
#   npm run build

# FROM gcr.io/distroless/nodejs20-debian12
# ARG BUILD_DATE
# ARG VCS_REF
# LABEL maintainer="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
#     org.opencontainers.image.title="RD Juice Shop" \
#     org.opencontainers.image.description="Probably the most modern and sophisticated insecure web application" \
#     org.opencontainers.image.authors="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
#     org.opencontainers.image.vendor="Open Worldwide Application Security Project" \
#     org.opencontainers.image.documentation="https://help.owasp-juice.shop" \
#     org.opencontainers.image.licenses="MIT" \
#     org.opencontainers.image.version="17.3.0" \
#     org.opencontainers.image.url="https://owasp-juice.shop" \
#     org.opencontainers.image.source="https://github.com/juice-shop/juice-shop" \
#     org.opencontainers.image.revision=$VCS_REF \
#     org.opencontainers.image.created=$BUILD_DATE
# WORKDIR /juice-shop
# COPY --from=installer --chown=65532:0 /juice-shop .
# COPY --chown=65532:0 --from=libxmljs-builder /juice-shop/node_modules/libxmljs ./node_modules/libxmljs
# USER 65532
# EXPOSE 3000
# CMD ["/juice-shop/build/app.js"]

# Stage 1: Install all dependencies, generate SBOM
FROM node:20-buster AS installer

COPY . /juice-shop
WORKDIR /juice-shop

# Install dependencies (DO NOT omit dev here!)
RUN npm install --unsafe-perm

# Optional build step (if needed before sbom)
RUN npm run build

# Install SBOM tool
ARG CYCLONEDX_NPM_VERSION=latest
RUN npm install -g @cyclonedx/cyclonedx-npm@$CYCLONEDX_NPM_VERSION

# Generate SBOM – works now because devDependencies are installed
RUN npm run sbom

# Prune devDependencies if you want to reduce final image size
RUN npm prune --omit=dev

# Clean up and set permissions as before
RUN mkdir logs \
    && chown -R 65532 logs \
    && chgrp -R 0 ftp/ frontend/dist/ logs/ data/ i18n/ \
    && chmod -R g=u ftp/ frontend/dist/ logs/ data/ i18n/ \
    && rm data/chatbot/botDefaultTrainingData.json || true \
    && rm ftp/legal.md || true \
    && rm i18n/*.json || true

# Stage 2: Build native libxmljs (optional)
FROM node:20-buster AS libxmljs-builder
WORKDIR /juice-shop
RUN apt-get update && apt-get install -y build-essential python3
COPY --from=installer /juice-shop/node_modules ./node_modules
RUN rm -rf node_modules/libxmljs/build && \
    cd node_modules/libxmljs && \
    npm run build

# Stage 3: Final minimal image
FROM gcr.io/distroless/nodejs20-debian12
WORKDIR /juice-shop

# Copy everything from installer stage
COPY --from=installer --chown=65532:0 /juice-shop .
COPY --chown=65532:0 --from=libxmljs-builder /juice-shop/node_modules/libxmljs ./node_modules/libxmljs

# Run as non-root user
USER 65532
EXPOSE 3000

CMD ["/juice-shop/build/app.js"]
