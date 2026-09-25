# Tools container: Bash, cron and sqlplus (Oracle Instant Client).
# Every project script runs here, so nothing Oracle-related has to be
# installed on the Windows host.
FROM debian:bookworm-slim

# Pinned Instant Client version (21c client for a 21c database).
ARG IC_VERSION=21.19.0.0.0dbru
ARG IC_URL=https://download.oracle.com/otn_software/linux/instantclient/2119000

# libaio1 is required by Instant Client; procps gives `ps`/`kill` for the lock-file check.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip libaio1 cron procps tzdata \
 && rm -rf /var/lib/apt/lists/*

# Install Instant Client (basic-lite + sqlplus). Registering the folder with ldconfig
# and linking sqlplus into /usr/local/bin means it also works from cron, which starts
# jobs with an almost empty environment (no custom PATH or LD_LIBRARY_PATH).
RUN mkdir -p /opt/oracle && cd /opt/oracle \
 && curl -fsSLO ${IC_URL}/instantclient-basiclite-linux.x64-${IC_VERSION}.zip \
 && curl -fsSLO ${IC_URL}/instantclient-sqlplus-linux.x64-${IC_VERSION}.zip \
 && unzip -qo instantclient-basiclite-linux.x64-${IC_VERSION}.zip \
 && unzip -qo instantclient-sqlplus-linux.x64-${IC_VERSION}.zip \
 && rm -f *.zip \
 && echo /opt/oracle/instantclient_21_19 > /etc/ld.so.conf.d/oracle-instantclient.conf \
 && ldconfig \
 && ln -s /opt/oracle/instantclient_21_19/sqlplus /usr/local/bin/sqlplus

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work
CMD ["/usr/local/bin/entrypoint.sh"]
