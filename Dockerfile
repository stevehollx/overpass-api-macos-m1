# Custom Overpass API build for Apple Silicon compatibility
FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    autotools-dev \
    automake \
    libtool \
    g++ \
    make \
    expat \
    libexpat1-dev \
    zlib1g-dev \
    libbz2-dev \
    libfcgi-dev \
    liblz4-dev \
    supervisor \
    nginx \
    fcgiwrap \
    wget \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Download and build Overpass API from source (as root)
WORKDIR /tmp
RUN wget http://dev.overpass-api.de/releases/osm-3s_v0.7.62.1.tar.gz \
    && tar -xzf osm-3s_v0.7.62.1.tar.gz \
    && cd osm-3s_v0.7.62.1 \
    && ./configure --prefix=/opt/osm3s --enable-lz4 \
    && make -j$(nproc) \
    && make install

# Create overpass user AFTER building
RUN useradd -r -s /bin/false overpass

# Set up directories with proper permissions (as root)
RUN mkdir -p /db /var/cache/overpass /var/log /var/run /tmp/overpass_sockets \
    && chmod 755 /db /var/cache/overpass /var/log /var/run /tmp/overpass_sockets \
    && chown -R overpass:overpass /db /var/cache/overpass /tmp/overpass_sockets

# Remove any supervisord installations (safeguard)
RUN rm -f /usr/bin/supervisord /usr/local/bin/supervisord 2>/dev/null || true

# Copy configuration files
COPY nginx.conf /etc/nginx/nginx.conf
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Expose port
EXPOSE 80

# Set environment variables
ENV OVERPASS_META=no
ENV OVERPASS_MODE=init
ENV OVERPASS_USE_AREAS=false

# Stay as root for the entrypoint to handle permissions
# The entrypoint script will handle user switching if needed
ENTRYPOINT ["/docker-entrypoint.sh"]