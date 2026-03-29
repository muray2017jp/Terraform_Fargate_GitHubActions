FROM php:8.2-fpm-bullseye

LABEL maintainer="ucan-lab <yes@u-can.pro>"

SHELL ["/bin/bash", "-oeux", "pipefail", "-c"]

# タイムゾーン・ロケール・Composer環境変数の設定
ENV TZ=UTC \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/composer

# Composer 2.x のコピー
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# 依存パッケージとPHP拡張（Redisを含む）のインストール
RUN apt-get update && \
    apt-get -y install git curl libicu-dev libonig-dev libzip-dev unzip locales && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    locale-gen en_US.UTF-8 && \
    # ロケールの生成
    localedef -f UTF-8 -i en_US en_US.UTF-8 && \
    # 必須PHP拡張のインストール
    docker-php-ext-install intl pdo_mysql zip bcmath && \
    # ★ Redis拡張のインストール（PECL）
    pecl install redis && \
    docker-php-ext-enable redis && \
    # ★ 重要：Nginxコンテナ等、外部からのFastCGI接続を許可するための設定
    sed -i 's|listen = 127.0.0.1:9000|listen = 0.0.0.0:9000|' /usr/local/etc/php-fpm.d/www.conf

# Node.js 18.x のインストール（フロントエンドビルド用）
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs

# 設定ファイルのコピー
COPY ./infra/docker/php/php-fpm.d/zzz-www.conf /usr/local/etc/php-fpm.d/zzz-www.conf
COPY ./infra/docker/php/php.ini /usr/local/etc/php/php.ini

# アプリケーションソースのコピーと権限設定
COPY --chown=www-data:www-data ./backend /work/backend

WORKDIR /work/backend

# ★ ここから追加：本番用のライブラリインストールを実行
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress

# 実行時：共有ボリューム用のディレクトリ作成とPHP-FPMの起動
CMD ["sh", "-c", "mkdir -p /var/run/php-fpm && chown -R www-data:www-data /var/run/php-fpm && php-fpm"]