#######################################################
### FIRST STAGE: build zipkin+opentracing modules
#######################################################
FROM tiredofit/alpine:3.9 AS builder

ARG OPENTRACING_CPP_VERSION=v1.5.1
ARG ZIPKIN_CPP_VERSION=v0.5.2
ARG NGINX_OPENTRACING_MODULE_VERSION=0.9.0

ENV NGINX_VERSION 1.15.10
ENV NGINX_OPENTRACING_MODULE nginx-opentracing-${NGINX_OPENTRACING_MODULE_VERSION}

### Download and build OpenTracing/Zipkin dependencies
RUN set -x \
  && apk update \
  && apk add git cmake gcc binutils build-base curl openssl-dev \
     pcre-dev zlib-dev curl-dev

## Build opentracing-cpp
RUN cd /tmp \
  && git clone -b $OPENTRACING_CPP_VERSION https://github.com/opentracing/opentracing-cpp.git \
  && cd opentracing-cpp \
  && mkdir .build && cd .build \
  && cmake -DCMAKE_BUILD_TYPE=Release \
           -DBUILD_TESTING=OFF .. \
  && make -j8 && make install

### Build zipkin-cpp-opentracing
RUN cd /tmp \
  && git clone -b $ZIPKIN_CPP_VERSION https://github.com/rnburn/zipkin-cpp-opentracing.git \
  && cd zipkin-cpp-opentracing \
  && mkdir .build && cd .build \
  && cmake -DBUILD_SHARED_LIBS=1 -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF .. \
  && make -j8 && make install

RUN cd /tmp \
  && ln -s /usr/local/lib/libzipkin_opentracing.so /usr/local/lib/libzipkin_opentracing_plugin.so

### Get nginx-opentracing
RUN cd /tmp \
  && wget https://github.com/opentracing-contrib/nginx-opentracing/archive/v${NGINX_OPENTRACING_MODULE_VERSION}.tar.gz -O ${NGINX_OPENTRACING_MODULE}.tar.gz

RUN cd /tmp \
  && tar zvxf ${NGINX_OPENTRACING_MODULE}.tar.gz

### Build the module in the nginx context
# Reuse same cli arguments as the nginx:alpine image used to build
RUN wget "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O nginx.tar.gz && \
  CONFARGS=$(nginx -V 2>&1 | sed -n -e 's/^.*arguments: //p') \
	tar -zxC /usr/src -f nginx.tar.gz && \
  cd /usr/src/nginx-$NGINX_VERSION && \
  ./configure --with-compat $CONFARGS --add-dynamic-module=/tmp/${NGINX_OPENTRACING_MODULE}/opentracing && \
  make -j8 && make install


#######################################################
### SECOND STAGE: final nginx + modules
#######################################################
FROM tiredofit/alpine:3.9

### Default Runtime Environment Variables
  ENV ENABLE_SMTP=TRUE

### Dependency Installation
  RUN set -x && \
      echo 'http://dl-4.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories && \
      apk update && \
      apk add \
          apache2-utils \
          ca-certificates \
          mariadb-client \
          openssl \
          nginx \
          php7-apcu \
          php7-amqp \
          php7-bcmath \
          php7-bz2 \
          php7-calendar \
          php7-ctype \
          php7-curl \
          php7-dba \
          php7-dom \
          php7-embed \
          php7-enchant \
          php7-exif \
          php7-fileinfo \
          php7-fpm \
          php7-ftp \
          php7-gd \
          php7-gettext \
          php7-gmp \
          php7-iconv \
          php7-imagick \
          php7-imap \
          php7-intl \
          php7-json \
          php7-ldap \
          php7-mailparse \
          php7-mbstring \
          php7-mcrypt \
          php7-memcached \
          php7-mysqli \
          php7-mysqlnd \
          php7-odbc \
          php7-opcache \
          php7-openssl \
          php7-pcntl \
          php7-pdo \
          php7-pdo_mysql \
          php7-pdo_pgsql \
          php7-pdo_sqlite \
          php7-pgsql \
          php7-phar\
          php7-posix \
          php7-pspell \
          php7-recode \
          php7-redis \
          php7-session \
          php7-shmop \
          php7-simplexml \
          php7-snmp \
          php7-soap \
          php7-sockets \
          php7-sqlite3 \
          php7-tidy \
          php7-tokenizer \
          php7-wddx \
          php7-xdebug \
          php7-xml \
          php7-xmlreader \
          php7-xmlrpc \
          php7-xmlwriter \
          php7-xml \
          php7-zip \
          php7-zlib \
          php7-zmq \
          && \
      \
      rm -rf /var/cache/apk/*

### Copy Zipkin modules
COPY --from=builder /usr/local/nginx/modules/ngx_http_opentracing_module.so /usr/local/nginx/modules/ngx_http_opentracing_module.so
COPY --from=builder /usr/local/lib/libzipkin_opentracing_plugin.so /usr/local/lib/libzipkin_opentracing_plugin.so
COPY --from=builder /usr/local/lib/libzipkin.so.0.5.2 /usr/local/lib/libzipkin.so.0.5.2
COPY --from=builder /usr/local/lib/libzipkin.so.0 /usr/local/lib/libzipkin.so.0
COPY --from=builder /usr/local/lib/libzipkin.so /usr/local/lib/libzipkin.so
COPY --from=builder /usr/local/lib/libopentracing.so.1.5.1 /usr/local/lib/libopentracing.so.1.5.1
COPY --from=builder /usr/local/lib/libopentracing.so.1 /usr/local/lib/libopentracing.so.1
COPY --from=builder /usr/local/lib/libopentracing.so /usr/local/lib/libopentracing.so

### Nginx and PHP7 Setup
RUN   sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g' /etc/php7/php.ini && \
      sed -i "s/nginx:x:100:101:nginx:\/var\/lib\/nginx:\/sbin\/nologin/nginx:x:100:101:nginx:\/www:\/bin\/bash/g" /etc/passwd && \
      sed -i "s/nginx:x:100:101:nginx:\/var\/lib\/nginx:\/sbin\/nologin/nginx:x:100:101:nginx:\/www:\/bin\/bash/g" /etc/passwd- && \
      ln -s /sbin/php-fpm7 /sbin/php-fpm && \
      \
### Install PHP Composer
      curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer && \
      \
### WWW  Installation
      mkdir -p /www/logs

### Networking Configuration
  EXPOSE 80

### Files Addition
  ADD install /
