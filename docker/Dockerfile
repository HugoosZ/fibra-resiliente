FROM pgrouting/pgrouting:17-3.5-3.7.3

# Bullseye usa el repositorio archivado de PostgreSQL.
RUN sed -i 's|http://apt.postgresql.org|https://apt-archive.postgresql.org|g' /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends postgis \
    && rm -rf /var/lib/apt/lists/*
