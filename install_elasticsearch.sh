#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
init "$@"

ES_VERSION=9.1.5
ES_HEAP=512m
ES_HOST=127.0.0.1
ES_PORT=9200
ES_KEYRING=/usr/share/keyrings/elasticsearch-keyring.gpg
ES_LIST=/etc/apt/sources.list.d/elastic-9.x.list
ES_YML=/etc/elasticsearch/elasticsearch.yml
ES_HEAP_OPTS=/etc/elasticsearch/jvm.options.d/heap.options
ES_SYSCTL=/etc/sysctl.d/99-elasticsearch.conf

changed=false

write_if_changed() {
    local dest=$1 tmp
    tmp=$(mktemp)
    cat > "$tmp"
    if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
        rm -f -- "$tmp"
        return 1
    fi
    install -m 644 "$tmp" "$dest"
    rm -f -- "$tmp"
    changed=true
    return 0
}

installed_version() {
    local out
    out=$(dpkg-query -W -f='${Status}\t${Version}' elasticsearch 2>/dev/null || true)
    awk -F'\t' '$1 ~ / installed$/ { print $2; exit }' <<< "$out"
}

current=$(installed_version)
if [[ -n "$current" && "$current" != "$ES_VERSION" && "$current" != "$ES_VERSION"-* ]]; then
    die "Уже установлен Elasticsearch ${current}; ожидается ${ES_VERSION}. Апгрейд запрещён."
fi

LOCAL_DEB="$ROOT_DIR/elasticsearch-${ES_VERSION}-amd64.deb"
apt-get install -y ca-certificates curl gnupg
rm -f -- /etc/apt/sources.list.d/elastic-8.x.list

if [[ -f "$LOCAL_DEB" ]]; then
    rm -f -- "$ES_LIST"
    apt_update
    apt-get install -y "$LOCAL_DEB"
    current=$(installed_version)
    [[ "$current" == "$ES_VERSION" || "$current" == "$ES_VERSION"-* ]] || die "Локальный пакет установил Elasticsearch ${current:-неизвестно}, ожидается ${ES_VERSION}."
elif curl -fsS --max-time 20 -o /dev/null https://artifacts.elastic.co/packages/9.x/apt/dists/stable/InRelease; then
    install -d -m 755 /usr/share/keyrings
    if [[ ! -f "$ES_KEYRING" ]]; then
        curl -fsSL --max-time 60 https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor --batch --yes -o "$ES_KEYRING"
        chmod 644 "$ES_KEYRING"
        changed=true
    fi
    write_if_changed "$ES_LIST" <<'LIST' || true
deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main
LIST
    apt_update
    apt-get install -y "elasticsearch=$ES_VERSION"
else
    die "artifacts.elastic.co недоступен. Положите elasticsearch-${ES_VERSION}-amd64.deb в $ROOT_DIR и повторите."
fi
apt-mark hold elasticsearch

write_if_changed "$ES_YML" <<YML || true
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
discovery.type: single-node
network.host: ${ES_HOST}
http.port: ${ES_PORT}
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
YML
chown root:elasticsearch "$ES_YML"
chmod 660 "$ES_YML"

# Debian postinst writes TLS passwords into the keystore; they conflict with security=false.
if [[ -x /usr/share/elasticsearch/bin/elasticsearch-keystore ]]; then
    while read -r setting; do
        [[ -z "$setting" ]] && continue
        /usr/share/elasticsearch/bin/elasticsearch-keystore remove --silent "$setting"
        changed=true
    done < <(/usr/share/elasticsearch/bin/elasticsearch-keystore list | grep -E '^xpack\.security\.(http|transport)\.ssl\.' || true)
fi

install -d -m 750 -o root -g elasticsearch /etc/elasticsearch/jvm.options.d
write_if_changed "$ES_HEAP_OPTS" <<HEAP || true
-Xms${ES_HEAP}
-Xmx${ES_HEAP}
HEAP
chown root:elasticsearch "$ES_HEAP_OPTS"
chmod 640 "$ES_HEAP_OPTS"

write_if_changed "$ES_SYSCTL" <<'SYSCTL' || true
vm.max_map_count=262144
SYSCTL
sysctl -w vm.max_map_count=262144 >/dev/null

systemctl daemon-reload
systemctl enable elasticsearch
if [[ "$changed" == true ]] || ! systemctl is-active --quiet elasticsearch; then
    systemctl restart elasticsearch
fi

deadline=$((SECONDS + 90))
es_body=
while (( SECONDS < deadline )); do
    if es_body=$(curl -fsS --max-time 5 "http://${ES_HOST}:${ES_PORT}" 2>/dev/null); then
        break
    fi
    sleep 2
done
[[ -n "$es_body" ]] || die "Elasticsearch не ответил на http://${ES_HOST}:${ES_PORT}"
printf '%s\n' "$es_body" | grep -q "\"number\"[[:space:]]*:[[:space:]]*\"${ES_VERSION}\"" \
    || die "Elasticsearch запущен, но версия не ${ES_VERSION}."
printf 'Elasticsearch %s слушает http://%s:%s\n' "$ES_VERSION" "$ES_HOST" "$ES_PORT"
