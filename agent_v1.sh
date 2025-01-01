#!/bin/sh

NZ_BASE_PATH="nezha"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

err() {
    printf "${red}%s${plain}\n" "$*" >&2
}

success() {
    printf "${green}%s${plain}\n" "$*"
}

info() {
    printf "${yellow}%s${plain}\n" "$*"
}

sudo() {
    myEUID=$(id -ru)
    if [ "$myEUID" -ne 0 ]; then
        if command -v sudo > /dev/null 2>&1; then
            command sudo "$@"
        else
            err "ERROR: sudo is not installed on the system, the action cannot be proceeded."
            exit 1
        fi
    else
        "$@"
    fi
}

deps_check() {
    deps="wget unzip grep curl"
    for dep in $deps; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            err "$dep not found, please install it first."
            exit 1
        fi
    done
}

geo_check() {
    api_list="https://blog.cloudflare.com/cdn-cgi/trace https://developers.cloudflare.com/cdn-cgi/trace"
    ua="Mozilla/5.0 (X11; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/81.0"
    for url in $api_list; do
        text="$(curl -A "$ua" -m 10 -s "$url")"
        if echo "$text" | grep -qw 'CN'; then
            isCN=true
            break
        fi
    done
}

env_check() {
    mach=$(uname -m)
    case "$mach" in
        amd64|x86_64) os_arch="amd64" ;;
        i386|i686) os_arch="386" ;;
        aarch64|arm64) os_arch="arm64" ;;
        *arm*) os_arch="arm" ;;
        s390x) os_arch="s390x" ;;
        riscv64) os_arch="riscv64" ;;
        mips) os_arch="mips" ;;
        mipsel|mipsle) os_arch="mipsle" ;;
        *) err "Unknown architecture: $mach" && exit 1 ;;
    esac

    system=$(uname)
    case "$system" in
        *Linux*) os="linux" ;;
        *Darwin*) os="darwin" ;;
        *FreeBSD*) os="freebsd" ;;
        *) err "Unknown system: $system" && exit 1 ;;
    esac
}

init() {
    deps_check
    env_check

    if [ -z "$CN" ]; then
        geo_check
        [ -n "$isCN" ] && CN=true
    fi

    [ -z "$CN" ] && GITHUB_URL="github.com" || GITHUB_URL="gitee.com"
}

install() {
    echo "Installing..."

    NZ_SERVICE_NAME=${NZ_SERVICE_NAME:-nezha-agent}

    if [ -z "$CN" ]; then
        NZ_AGENT_URL="https://${GITHUB_URL}/nezhahq/agent/releases/latest/download/nezha-agent_${os}_${os_arch}.zip"
    else
        _version=$(curl -m 10 -sL "https://gitee.com/api/v5/repos/naibahq/agent/releases/latest" | awk -F '"' '{for(i=1;i<=NF;i++){if($i=="tag_name"){print $(i+2)}}}')
        NZ_AGENT_URL="https://${GITHUB_URL}/naibahq/agent/releases/download/${_version}/nezha-agent_${os}_${os_arch}.zip"
    fi

    _cmd="wget -T 60 -O /tmp/nezha-agent_${os}_${os_arch}.zip $NZ_AGENT_URL >/dev/null 2>&1"
    if ! eval "$_cmd"; then
        err "Download nezha-agent release failed, check your network connectivity"
        exit 1
    fi

    sudo mkdir -p "$NZ_AGENT_PATH"
    sudo unzip -qo /tmp/nezha-agent_${os}_${os_arch}.zip -d "$NZ_AGENT_PATH" &&
        sudo rm -rf /tmp/nezha-agent_${os}_${os_arch}.zip

    random=$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 5)
    path="$NZ_AGENT_PATH/config-${NZ_SERVICE_NAME}-$random.yml"

    if [ -z "$NZ_SERVER" ]; then
        err "NZ_SERVER should not be empty"
        exit 1
    fi

    if [ -z "$NZ_CLIENT_SECRET" ]; then
        err "NZ_CLIENT_SECRET should not be empty"
        exit 1
    fi

    env="NZ_SERVER=$NZ_SERVER NZ_CLIENT_SECRET=$NZ_CLIENT_SECRET NZ_TLS=$NZ_TLS NZ_DISABLE_AUTO_UPDATE=$NZ_DISABLE_AUTO_UPDATE NZ_DISABLE_FORCE_UPDATE=$DISABLE_FORCE_UPDATE NZ_DISABLE_COMMAND_EXECUTE=$NZ_DISABLE_COMMAND_EXECUTE NZ_SKIP_CONNECTION_COUNT=$NZ_SKIP_CONNECTION_COUNT"

    sudo "${NZ_AGENT_PATH}/nezha-agent" service -c "$path" uninstall >/dev/null 2>&1 || true
    _cmd="sudo env $env $NZ_AGENT_PATH/nezha-agent service -c $path install --name $NZ_SERVICE_NAME"
    if ! eval "$_cmd"; then
        err "Install nezha-agent service failed"
        sudo "${NZ_AGENT_PATH}/nezha-agent" service -c "$path" uninstall >/dev/null 2>&1
        exit 1
    fi

    success "nezha-agent successfully installed with service name: $NZ_SERVICE_NAME"
}

uninstall() {
    sudo find "$NZ_AGENT_PATH" -type f -name "*config*.yml" | while read -r file; do
        sudo "$NZ_AGENT_PATH/nezha-agent" service -c "$file" uninstall
        sudo rm "$file"
    done
    info "Uninstallation completed."
}

if [ "$1" = "uninstall" ]; then
    uninstall
    exit
fi

init
install