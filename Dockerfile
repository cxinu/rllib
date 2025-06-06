FROM openresty/openresty:buster

RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    unzip \
    libpq-dev \
    lua5.1 \
    liblua5.1-0-dev \
    luarocks \
    && rm -rf /var/lib/apt/lists/*

RUN luarocks --lua-version=5.1 install pgmoon

RUN mkdir -p /app/logs
WORKDIR /app

COPY conf /app/conf
COPY lualib /app/lualib

EXPOSE 8080

CMD ["openresty", "-p", "/app", "-c", "conf/nginx.conf", "-g", "daemon off;"]
