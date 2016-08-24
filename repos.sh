#!/bin/sh

staging_repo=/srv/gnome-sdk/public_html/staging/repo
stable_runtime_repo=/srv/gnome-sdk/public_html/repo
stable_app_repo=/srv/gnome-sdk/public_html/repo-apps
stable_remotes="sdkbuilder1 aarch64-stable arm-stable"
runtime_regexp="^runtime/\(org.gnome.\(Sdk\|Platform\)\|org.freedesktop.\(Base\)\?\(Sdk\|Platform\)\)"
stable_gpg_args="--gpg-homedir=/srv/gnome-sdk/gnupg --gpg-sign=55D15281"

set -e
set -u
set -x

function pullStableRemote() {
    local remote=$1
    ostree --repo=${staging_repo} pull --mirror ${remote}
}

function pullStableAll() {
    for r in ${stable_remotes}; do
	pullStableRemote ${r}
    done
}

function listStableRefs() {
    ostree --repo=${staging_repo} refs | grep -v ^appstream/ | LC_COLLATE=C sort
}

function listStableRuntimeRefs() {
    listStableRefs | grep ${runtime_regexp}
}

function listStableAppRefs() {
    listStableRefs | grep -v ${runtime_regexp}
}

function getSummary() {
    local repo=$1
    local ref=$2

    ostree show --repo=${repo} ${ref} | head -4 | tail -1 | sed "s/^    //"
}

function mergeRefs() {
    local destrepo=$1
    local srcrepo=$2
    local refs=$3
    local gpg_args=$4

    flatpak build-commit-from --no-update-summary --src-repo=${srcrepo} ${gpg_args-} ${destrepo} ${refs-}
}

arg_pull_stable=false
arg_update_stable_apps=false
arg_update_stable_runtimes=false
arg_merge_stable_apps=false
arg_merge_stable_runtimes=false
arg_disable_deltas=false

function usage () {
    echo "Usage: "
    echo "  repos.sh [OPTIONS]"
    echo
    echo "Options:"
    echo
    echo "  -h --help                      Display this help message and exit"
    echo "  --pull-stable                  Pull stable remotes into staging repo"
    echo "  --merge-stable                 Merge stable apps + runtimes"
    echo "  --merge-stable-apps            Merge stable apps"
    echo "  --merge-stable-runtimes        Merge stable runtimes"
    echo "  --disable-deltas               Don't create static deltas"
    echo
}


while : ; do
    case "${1-}" in
	-h|--help)
	    usage;
	    exit 0;
	    shift ;;

	--pull-stable)
	    arg_pull_stable=true
	    shift ;;

	--merge-stable)
	    arg_merge_stable_apps=true
	    arg_merge_stable_runtimes=true
	    shift ;;

	--merge-stable-apps)
	    arg_merge_stable_apps=true
	    shift ;;

	--merge-stable-runtimes)
	    arg_merge_stable_runtimes=true
	    shift ;;

	--disable-deltas)
	    arg_disable_deltas=true
	    shift ;;

	*)
	    break ;;
    esac
done

if $arg_pull_stable; then
    pullStableAll
fi

if $arg_merge_stable_runtimes; then
    mergeRefs ${stable_runtime_repo} ${staging_repo} "$(listStableRuntimeRefs)" "${stable_gpg_args}"
    arg_update_stable_runtimes=true
fi

if $arg_merge_stable_apps; then
    mergeRefs ${stable_app_repo} ${staging_repo} "$(listStableAppRefs)" "${stable_gpg_args}"
    arg_update_stable_apps=true
fi

delta_args=--generate-static-deltas
if $arg_disable_deltas; then
    delta_args=
fi

if $arg_update_stable_runtimes; then
    flatpak build-update-repo ${delta_args} ${stable_gpg_args} ${stable_runtime_repo}
fi

if $arg_update_stable_apps; then
    flatpak build-update-repo  ${delta_args} ${stable_gpg_args} ${stable_app_repo}
fi
