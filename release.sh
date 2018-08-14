#!/bin/bash

# release.sh

# Set default branch names and suffixes
DEVELOP_BRANCH="develop"
MASTER_BRANCH="master"
RELEASE_CANDIDATE_SUFFIX="rc"
FIX_TYPE="fix"
HOTFIX_TYPE="hotfix"
IMPROVEMENT_TYPE="imp"
FEATURE_TYPE="feat"
GENERIC_TYPE="n/a"
VERSION_FILE="version.txt"

function print_usage() {
    echo "Usage: release.sh OPTION [ARGUMENTS...]" >&2
    echo "Description: Creates a new release candidate branch or upgrades current release version. " >&2
    echo "OPTIONS: " >&2
    echo "-c Create release. " >&2
    echo "   Arguments: " >&2
    echo "     message: Will be used as git tag message." >&2
    echo "-u Upgrade current release. Depending on log history since last tag for current commit." >&2
    exit 1
}

function validate_arguments() {
    if [ "$#" -eq 0 ]; then
        print_usage
    elif [ "${1}" == "-c" ] && [ "$#" -lt 2 ]; then
        echo "A message describing the new release must be supplied when using option -c" >&2
        exit 1
    fi
}

function get_last_version_data() {
    # Recover version data from Git
    last_tag=$(git describe --abbrev=0)
    last_version=$(echo ${last_tag} | grep -oP "v\K\d+\.\d\.\d\.\d(?=[\-\w]*)")
    last_label=$(echo ${last_tag} | grep -oP "v\d+\.\d\.\d\.\d\-\K\w*")
    last_commit_message=$(git log --format=%B -n 1)
    last_commit_info=($(echo "${last_commit_message}" | tr ' ' '\n'))
    # Possible commit types: fix, hotfix, imp, feat, n/a
    type=${last_commit_info[1]}
    current_branch=$(git branch | grep -oP "\*\s\K.+")
    # Extract version components in the format W.X.Y.Z
    version_components=($(echo "${last_version}" | tr '.' '\n'))
}

function update_version_file() {
    local new_version="${1}"
    sed "s/${last_tag}/v${new_version}/" ${VERSION_FILE} > tmp.txt && mv tmp.txt ${VERSION_FILE}
}

function create_release_candidate() {
    local tag_message="${1}"
    # Create a release candidate only when develop is the origin
    if [ ${current_branch} == ${DEVELOP_BRANCH} ]; then
        # Increase version 'X' component with each new release. Reset to zero 'Y' and 'Z' components.
        release_version=$(echo "${version_components[0]}."$((${version_components[1]} + 1))".0.0")
        release_version=$(echo "${release_version}-${RELEASE_CANDIDATE_SUFFIX}")
        # Tag develop commit from which release is created
        git tag -a "v${release_version}" -m "${tag_message}"
        git push origin --tags
        # Create release branch
        git checkout -b "${release_version}"
        # Update version file
        update_version_file "${release_version}"
        git add ${VERSION_FILE}
        git commit -m "[n/a] n/a Release ${release_version} branch created."
        git push origin "${release_version}"
    else
        echo "Release candidate branches should only be created from develop branch!" >&2
        echo "Aborting release creation." >&2
        exit 1
    fi
}

function scan_previous_commits(){
    # Number of commits since last tag
    commits_since_last_tag=$(git describe --long| grep -oP '\d+(?=\-[\w\d]{8}$)')
    types_since_last_tag=($(git log --reverse -n "${commits_since_last_tag}" --format=%B | grep -oP '(?<=\]\s)[\w\/]+(?=\s)'))
    for type in "${types_since_last_tag[@]}"
    do :
        if [ ${type} == ${FIX_TYPE} ] || [ ${type} == ${HOTFIX_TYPE} ]; then
            # Increase version 'Y' component with each bug fix. Reset 'Z' to zero
            let version_components[2]++
            let version_components[3]=0
        elif [ ${type} == ${IMPROVEMENT_TYPE} ] || [ ${type} == ${GENERIC_TYPE} ]; then
            # Increase version 'Z' component with each improvement.
            let version_components[3]++
        elif [ ${type} == ${FEATURE_TYPE} ]; then
            # New features should not be allowed in release branches.
            echo "Commits associated to new functionality should not be applied to release branches." >&2
            echo "Aborting release upgrade." >&2
            exit 1
        fi
    done
}

function upgrade_release() {
    scan_previous_commits
    release_version=$(echo "${version_components[0]}.${version_components[1]}.${version_components[2]}.${version_components[3]}")
    # Add rc suffix if branch being upgraded is a release candidate.
    if [[ ${current_branch} == *"rc"* ]]; then
      release_version=$(echo "${release_version}-${RELEASE_CANDIDATE_SUFFIX}")  
    fi
    update_version_file "${release_version}"
    git add "${VERSION_FILE}"
    git commit -m "[n/a] n/a Release ${release_version} upgrade applied."
    last_commit_message=$(git log --format=%B -n 1)
    git tag -a "v${release_version}" -m "${last_commit_message}"
    git push origin "${current_branch}"
    git push origin --tags
}

function main() {
    #  Exit immediately if a command exits with a non-zero status.
    # set -e
    # Command options.
    option="${1}"
    message="${2}"

    validate_arguments "$@"
    get_last_version_data

    if [ ${option} == "-c" ]; then
        create_release_candidate "${message}"
    elif [ ${option} == "-u" ]; then
        upgrade_release
    fi

    return 0
}

main "$@"
