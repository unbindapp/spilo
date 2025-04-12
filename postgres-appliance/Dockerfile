ARG BASE_IMAGE=ubuntu:24.04
ARG PGVERSION=17

# === First stage: build dependencies ===
FROM $BASE_IMAGE as dependencies-builder
ENV WALG_VERSION=v3.0.3
COPY build_scripts/dependencies.sh /builddeps/
COPY dependencies/debs /builddeps/
RUN bash /builddeps/dependencies.sh

# === Second stage: locale preparation ===
FROM ubuntu:18.04 as locale-builder
COPY build_scripts/locales.sh /builddeps/
RUN bash /builddeps/locales.sh

# === Main build stage ===
FROM $BASE_IMAGE as builder
ARG PGVERSION
ARG ADDITIONAL_LOCALES=""

# Set PostgreSQL version and extension versions
ENV POSTGIS_VERSION=3.5 \
    BG_MON_COMMIT=7f5887218790b263fe3f42f85f4ddc9c8400b154 \
    PG_AUTH_MON_COMMIT=fe099eef7662cbc85b0b79191f47f52f1e96b779 \
    PG_MON_COMMIT=ead1de70794ed62ca1e34d4022f6165ff36e9a91 \
    SET_USER=REL4_1_0 \
    PLPROFILER=REL4_2_5 \
    PG_PROFILE=4.7 \
    PAM_OAUTH2=v1.0.1 \
    PG_PERMISSIONS_COMMIT=f4b7c18676fa64236a1c8e28d34a35764e4a70e2 \
    PATRONIVERSION=4.0.4 \
    WALE_VERSION=1.1.1

# Copy build scripts and prepare the system
COPY build_scripts/prepare.sh build_scripts/locales.sh /builddeps/
RUN bash /builddeps/prepare.sh

# Copy locale archive from the locale builder
COPY --from=locale-builder /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.18

# Copy dependencies and build scripts
COPY cron_unprivileged.c /builddeps/
COPY build_scripts/base.sh /builddeps/
COPY --from=dependencies-builder /builddeps/*.deb /builddeps/

# Install PostgreSQL and extensions in a single RUN to reduce layers
WORKDIR /builddeps
RUN bash base.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy wal-g and install patroni and wal-e
COPY --from=dependencies-builder /builddeps/wal-g /usr/local/bin/
COPY build_scripts/patroni_wale.sh /builddeps/
RUN bash /builddeps/patroni_wale.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    # Remove unnecessary files
    rm -rf /usr/share/doc /usr/share/man /usr/share/info && \
    find /var/log -type f -delete && \
    find /usr/lib/python* -name '__pycache__' -exec rm -r {} + || true && \
    find /usr/local/lib/python* -name '__pycache__' -exec rm -r {} + || true

# === Final stage ===
FROM scratch
COPY --from=builder / /

# Set environment variables
ENV LC_ALL=en_US.utf-8 \
    PATH=$PATH:/usr/lib/postgresql/$PGVERSION/bin \
    PGHOME=/home/postgres \
    RW_DIR=/run \
    DEMO=false \
    USE_OLD_LOCALES=false

ENV WALE_ENV_DIR=$RW_DIR/etc/wal-e.d/env \
    LOG_ENV_DIR=$RW_DIR/etc/log.d/env \
    PGROOT=$PGHOME/pgdata/pgroot \
    PGDATA=$PGHOME/pgdata/pgroot/data \
    PGLOG=$PGHOME/pgdata/pgroot/pg_log

# Setup final configuration
WORKDIR $PGHOME
COPY motd /etc/
COPY runit /etc/service/
COPY pgq_ticker.ini $PGHOME/
COPY scripts bootstrap major_upgrade /scripts/
COPY launch.sh /

EXPOSE 5432 8008 8080
CMD ["/bin/sh", "/launch.sh", "init"]