FROM openresty/openresty:buster

RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    unzip \
    fish \
    ranger \
    libpq-dev \
    lua5.1 \
    liblua5.1-0-dev \
    luarocks \
    && rm -rf /var/lib/apt/lists/*

RUN luarocks install kong-redis-cluster # use "luarocks install rllib" instead

RUN mkdir -p /app/logs
WORKDIR /app

COPY examples /app
# remove this in future
COPY lib /app 

EXPOSE 8080

CMD ["openresty", "-p", "/app", "-c", "nginx.conf", "-g", "daemon off;"]
