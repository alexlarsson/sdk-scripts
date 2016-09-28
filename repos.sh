#!/bin/sh

if [ -L $0 ] ; then
    DIR=$(dirname $(readlink -f $0)) ;
else
    DIR=$(dirname $0) ;
fi

set -e
set -u

HTML=$DIR/public_html

runtime_regexp="^runtime/\(org.gnome.\(Sdk\|Platform\)\|org.freedesktop.\(Base\)\?\(Sdk\|Platform\)\)"
gnome_runtime_regexp="^runtime/org.gnome.\(Sdk\|Platform\)"

stable_staging_repo=$HTML/staging/repo
stable_remotes="sdkbuilder1 aarch64-stable arm-stable"

nightly_staging_repo=$HTML/staging/repo-nightly
nightly_remotes="sdkbuilder1 aarch64-unstable arm-unstable"

stable_runtime_repo=$HTML/repo
stable_app_repo=$HTML/repo-apps

nightly_runtime_repo=$HTML/nightly/repo
nightly_app_repo=$HTML/nightly/repo-apps

stable_gpg_args="--gpg-homedir=/srv/gnome-sdk/gnupg --gpg-sign=55D15281"
nightly_gpg_args="--gpg-homedir=/srv/gnome-sdk/gnupg-nightly --gpg-sign=82170E3D"

STABLE_LIST=()
NIGHTLY_LIST=()
declare -A REPO
declare -A REMOTES
declare -A MATCH_BRANCHES
declare -A NOMATCH_BRANCHES

STABLE_LIST+=("stable-fdo")
REPO["stable-fdo"]="$stable_staging_repo"
REMOTES["stable-fdo"]="sdkbuilder1 aarch64-stable-3-22 arm-stable-3-22"
MATCH_BRANCHES["stable-fdo"]="^runtime/org.freedesktop.(Base)?(Sdk|Platform)"
NOMATCH_BRANCHES["stable-fdo"]=""

STABLE_LIST+=("stable-gnome-3-20")
REPO["stable-gnome-3-20"]="$stable_staging_repo"
REMOTES["stable-gnome-3-20"]="sdkbuilder1 aarch64-stable-3-20 arm-stable-3-20"
MATCH_BRANCHES["stable-gnome-3-20"]="^runtime/org.gnome.(Sdk|Platform).*/.*/3.20"
NOMATCH_BRANCHES["stable-gnome-3-20"]=""

STABLE_LIST+=("stable-gnome-3-22")
REPO["stable-gnome-3-22"]="$stable_staging_repo"
REMOTES["stable-gnome-3-22"]="sdkbuilder1 aarch64-stable-3-22 arm-stable-3-22"
MATCH_BRANCHES["stable-gnome-3-22"]="^runtime/org.gnome.(Sdk|Platform).*/.*/3.22"
NOMATCH_BRANCHES["stable-gnome-3-22"]=""

STABLE_LIST+=("stable-gnome-apps")
REPO["stable-gnome-apps"]="$stable_staging_repo"
REMOTES["stable-gnome-apps"]="sdkbuilder1 aarch64-stable-3-22 arm-stable-3-22"
NOMATCH_BRANCHES["stable-gnome-apps"]="^runtime/org.(gnome|freedesktop).(Base)?(Sdk|Platform)"
MATCH_BRANCHES["stable-gnome-apps"]=""

NIGHTLY_LIST+=("unstable-gnome")
REPO["unstable-gnome"]="$nightly_staging_repo"
REMOTES["unstable-gnome"]="sdkbuilder1 aarch64-unstable arm-unstable"
MATCH_BRANCHES["unstable-gnome"]="^runtime/org.gnome.(Sdk|Platform).*/.*/master"
NOMATCH_BRANCHES["unstable-gnome"]=""

NIGHTLY_LIST+=("unstable-gnome-apps")
REPO["unstable-gnome-apps"]="$nightly_staging_repo"
REMOTES["unstable-gnome-apps"]="sdkbuilder1 aarch64-unstable arm-unstable"
NOMATCH_BRANCHES["unstable-gnome-apps"]="^runtime/org.(gnome|freedesktop).(Base)?(Sdk|Platform)"
MATCH_BRANCHES["unstable-gnome-apps"]=""

function stage() {
    local id=$1
    local repo=${REPO[$id]}
    local remotes=${REMOTES[$id]}
    local match_branches=${MATCH_BRANCHES[$id]}
    local nomatch_branches=${NOMATCH_BRANCHES[$id]}

    echo Staging $id
    echo ============
    for remote in $remotes; do
        refs=""
        for ref in $(ostree --repo=${repo} remote refs $remote  | sed "s/^.*\://" | grep -v ^appstream/ | LC_COLLATE=C sort); do
            if [[ "$match_branches" != "" && "$ref" =~ $match_branches ]] ; then
                refs="$refs $ref"
            fi
            if [[ "$nomatch_branches" != "" && ! "$ref" =~ $nomatch_branches ]] ; then
                refs="$refs $ref"
            fi
        done
        if [ "$refs" != "" ]; then
            ostree --repo=${repo} pull --mirror ${remote} ${refs}
        fi
    done
}

function stageAll() {
    local list="$*"
    for id in $list; do
        stage $id
    done
}

function mergeRefs() {
    local destrepo=$1
    local srcrepo=$2
    local refs=$3
    local gpg_args=$4

    flatpak build-commit-from --no-update-summary --src-repo=${srcrepo} ${gpg_args-} ${destrepo} ${refs-}
}

function pullStableAll() {
    stageAll "${STABLE_LIST[@]}"
}

function pullNightlyAll() {
    stageAll "${NIGHTLY_LIST[@]}"
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
