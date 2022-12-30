#! /usr/bin/env nix-shell
#! nix-shell -i bash -p jq curl zip

script_directory=$(dirname "$(readlink -f "${BASH_SOURCE[0]:-"$0"}")")
output_directory=$(readlink -f "${script_directory}/..")

function gh() {
    curl --silent					\
	-H "Accept: application/vnd.github+json"	\
	-H "X-GitHub-Api-Version: 2022-11-28"		\
	"https://api.github.com/${1}"
}

function gh_repo() {
    owner="$1"
    repo="$2"

    path="$3"
    
    gh "repos/${owner}/${repo}/${path}"
}

function gh_releases() {
    owner="$1"
    repo="$2"

    gh_repo "${owner}" "${repo}" "releases" | \
    jq --compact-output --raw-output '.[] as { $tag_name, $assets }
	    | $tag_name | capture("v(?<version>[.0-9]+(-\\w+)?)") as { version: $version }
	    | $assets[]
	    | .browser_download_url + ";"
	      	+ (.name
			| capture("(?<component>.+?)-\($version)(-(?<platform>.+?))?(\\.\\w+)+")
			| .component + ";"
		+ if .platform then .platform else "_" end + ";"
		+ $version)'

}

manifest_directory="${output_directory}/manifest"
mkdir -p "${manifest_directory}"

function build_manifest() {
    path="$1"
    url="$2"
    hash="$3"

    jq --compact-output --raw-output --null-input \
       --arg 'url'  "${url}"			  \
       --arg 'hash' "${hash}"			  \
       --arg 'path' "${path}"                     \
       '{ $hash, $path, $url }'
}

function create_manifest_file() {
    shopt -s extglob

    url="$1"
    platform="$2"
    version="$3"

    platform="${platform/'unknown-linux-gnu'/'linux'}"
    platform="${platform/'apple-darwin'/'darwin'}"
    
    manifest_prefix="${manifest_directory}/${version}/${platform}"

    if [[ "${url}" == *.tar.* ]];
    then
	archive_name=$(basename "${url}")

	printf ">> FETCH %s\n" "${archive_name}" 1>&2 
	prefetched=$(nix store prefetch-file --hash-type 'sha256' --json "${url}" 2>/dev/null)
	hash=$(jq --compact-output --raw-output '.hash' <<<"${prefetched}")
	store_path=$(jq --compact-output --raw-output '.storePath' <<<"${prefetched}")

	extraction_tmp=$(mktemp -d)

	printf ">> EXTRACT %s\n" "${archive_name}" 1>&2 
	tar --extract --file "${store_path}" -C "${extraction_tmp}"

	components_file=$(find "${extraction_tmp}" -name 'components' -printf '%P')
	archive_root=$(dirname "${components_file}")

	for component in $(cat "${extraction_tmp}/${components_file}");
	do
	    if [[ -d "${extraction_tmp}/${archive_root}/${component}" ]];
	    then
		printf ">> FOUND %s\n" "${version}/${platform}/${component}"
		mkdir -p "${manifest_prefix}"
		build_manifest "${archive_root}/${component}/" "${url}" "${hash}" > "${manifest_prefix}/${component}.json"
	    else
		printf ">> MISSING %s in %s\n" "${archive_root}/${component}" "${archive_name}"
	    fi
	done

	rm -rf "${extraction_tmp}"
    fi
}

function build_manifests() {    
    # https://stackoverflow.com/questions/16591290/parallelizing-a-while-loop-with-arrays-read-from-a-file-in-bash
    while IFS=";" read -r url component platform version;
    do 
	( create_manifest_file "${url}" "${platform}" "${version}" ) &

	[ $( jobs | wc -l ) -ge $( nproc ) ] && wait
    done

    wait
}

gh_releases "esp-rs" "rust-build" | build_manifests

