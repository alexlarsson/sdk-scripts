#!/bin/sh

stable_staging_repo=/srv/gnome-sdk/public_html/staging/repo
stable_remotes="sdkbuilder1 aarch64-stable arm-stable"

nightly_staging_repo=/srv/gnome-sdk/public_html/staging/repo-nightly
nightly_remotes="sdkbuilder1 aarch64-unstable arm-unstable"

stable_runtime_repo=/srv/gnome-sdk/public_html/repo
stable_app_repo=/srv/gnome-sdk/public_html/repo-apps

nightly_runtime_repo=/srv/gnome-sdk/public_html/nightly/repo
nightly_app_repo=/srv/gnome-sdk/public_html/nightly/repo-apps

stable_gpg_args="--gpg-homedir=/srv/gnome-sdk/gnupg --gpg-sign=55D15281"
nightly_gpg_args="--gpg-homedir=/srv/gnome-sdk/gnupg-nightly --gpg-sign=82170E3D"

runtime_regexp="^runtime/\(org.gnome.\(Sdk\|Platform\)\|org.freedesktop.\(Base\)\?\(Sdk\|Platform\)\)"
gnome_runtime_regexp="^runtime/org.gnome.\(Sdk\|Platform\)"

set -e
set -u

function mergeRefs() {
    local destrepo=$1
    local srcrepo=$2
    local refs=$3
    local gpg_args=$4

    flatpak build-commit-from --no-update-summary --src-repo=${srcrepo} ${gpg_args-} ${destrepo} ${refs-}
}

function pullStableRemote() {
    local remote=$1
    ostree --repo=${stable_staging_repo} pull --mirror ${remote}
}

function pullStableAll() {
    for r in ${stable_remotes}; do
	pullStableRemote ${r}
    done
}

function pullNightlyRemote() {
    local remote=$1
    ostree --repo=${nightly_staging_repo} pull --mirror ${remote}
}

function pullNightlyAll() {
    for r in ${nightly_remotes}; do
	pullNightlyRemote ${r}
    done
}

function listStableRefs() {
    ostree --repo=${stable_staging_repo} refs | grep -v ^appstream/ | LC_COLLATE=C sort
}

function listStableRuntimeRefs() {
    listStableRefs | grep ${runtime_regexp}
}

function listStableAppRefs() {
    listStableRefs | grep -v ${runtime_regexp}
}

function listNightlyRefs() {
    ostree --repo=${nightly_staging_repo} refs | grep -v ^appstream/ | LC_COLLATE=C sort
}

function listNightlyRuntimeRefs() {
    listNightlyRefs | grep ${gnome_runtime_regexp}
}

function listNightlyAppRefs() {
    listNightlyRefs | grep -v ${runtime_regexp}
}

arg_pull_stable=false
arg_pull_nightly=false
arg_update_stable_apps=false
arg_update_stable_runtimes=false
arg_update_nightly_apps=false
arg_update_nightly_runtimes=false
arg_merge_stable_apps=false
arg_merge_stable_runtimes=false
arg_merge_nightly_apps=false
arg_merge_nightly_runtimes=false
arg_disable_deltas=false

function usage () {
    echo "Usage: "
    echo "  repos.sh [OPTIONS]"
    echo
    echo "Options:"
    echo
    echo "  -h --help                      Display this help message and exit"
    echo "  --pull-stable                  Pull stable remotes into staging repo"
    echo "  --pull-nightly                 Pull nightly remotes into staging repo"
    echo "  --merge-stable                 Merge stable apps + runtimes"
    echo "  --merge-stable-apps            Merge stable apps"
    echo "  --merge-stable-runtimes        Merge stable runtimes"
    echo "  --merge-nightly                Merge nightly apps + runtimes"
    echo "  --merge-nightly-apps           Merge nightly apps"
    echo "  --merge-nightly-runtimes       Merge nightly runtimes"
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

	--pull-nightly)
	    arg_pull_nightly=true
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

	--merge-nightly)
	    arg_merge_nightly_apps=true
	    arg_merge_nightly_runtimes=true
	    shift ;;

	--merge-nightly-apps)
	    arg_merge_nightly_apps=true
	    shift ;;

	--merge-nightly-runtimes)
	    arg_merge_nightly_runtimes=true
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

if $arg_pull_nightly; then
    pullNightlyAll
fi

delta_args=--generate-static-deltas
if $arg_disable_deltas; then
    delta_args=
fi

if $arg_merge_stable_runtimes; then
    mergeRefs ${stable_runtime_repo} ${stable_staging_repo} "$(listStableRuntimeRefs)" "${stable_gpg_args}"
    arg_update_stable_runtimes=true
fi

if $arg_update_stable_runtimes; then
    flatpak build-update-repo --prune ${delta_args} ${stable_gpg_args} ${stable_runtime_repo}
fi

if $arg_merge_stable_apps; then
    mergeRefs ${stable_app_repo} ${stable_staging_repo} "$(listStableAppRefs)" "${stable_gpg_args}"
    arg_update_stable_apps=true
fi

if $arg_update_stable_apps; then
    flatpak build-update-repo --prune ${delta_args} ${stable_gpg_args} ${stable_app_repo}
fi

if $arg_merge_nightly_runtimes; then
    mergeRefs ${nightly_runtime_repo} ${nightly_staging_repo} "$(listNightlyRuntimeRefs)" "${nightly_gpg_args}"
    arg_update_nightly_runtimes=true
fi

if $arg_update_nightly_runtimes; then
    flatpak build-update-repo --prune --prune-depth=10 ${delta_args} ${nightly_gpg_args} ${nightly_runtime_repo}
fi

if $arg_merge_nightly_apps; then
    mergeRefs ${nightly_app_repo} ${nightly_staging_repo} "$(listNightlyAppRefs)" "${nightly_gpg_args}"
    arg_update_nightly_apps=true
fi

if $arg_update_nightly_apps; then
    flatpak build-update-repo --prune --prune-depth=10 ${delta_args} ${nightly_gpg_args} ${nightly_app_repo}
fi
