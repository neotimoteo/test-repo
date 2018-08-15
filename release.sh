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
current_branch=$(git branch | grep -oP "\*\s\K.+")

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
    local include_first_parent="${1}"
    # Recover version data from Git
    if [ ! -z ${1} ]; then
        last_tag=$(git describe "${include_first_parent}" --abbrev=0)
    else
        last_tag=$(git describe --abbrev=0)
    fi
    last_version=$(echo ${last_tag} | grep -oP "v\K\d+\.\d\.\d\.\d(?=[\-\w]*)")
    last_label=$(echo ${last_tag} | grep -oP "v\d+\.\d\.\d\.\d\-\K\w*")
    last_commit_message=$(git log --format=%B -n 1)
    last_commit_info=($(echo "${last_commit_message}" | tr ' ' '\n'))
    # Possible commit types: fix, hotfix, imp, feat, n/a
    last_commit_type=${last_commit_info[1]}
    # Extract git version components in the format W.X.Y.Z
    version_components=($(echo "${last_version}" | tr '.' '\n'))
    # Recover version data from version file
    tag_in_file=$(cat "${VERSION_FILE}")
    label_in_file=$(echo "${tag_in_file}" | grep -oP "v\d+\.\d\.\d\.\d\-\K\w*")
    version_in_file=$(echo "${tag_in_file}" | grep -oP "v\K\d+\.\d\.\d\.\d(?=[\-\w]*)")
    # Extract file version components in the format W.X.Y.Z
    version_components_in_file=($(echo "${version_in_file}" | tr '.' '\n'))
}

function update_version_file() {
    local new_version="${1}"
    sed "s/${tag_in_file}/v${new_version}/" ${VERSION_FILE} > tmp.txt && mv tmp.txt ${VERSION_FILE}
}

function create_release_candidate() {
    local tag_message="${1}"
    get_last_version_data --first-parent
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

function upgrade_release_candidate() {
    get_last_version_data
    calculate_version
    release_version=$(echo "${version_components[0]}.${version_components[1]}.${version_components[2]}.${version_components[3]}")
    # Add rc suffix if branch being upgraded is a release candidate.
    release_version=$(echo "${release_version}-${RELEASE_CANDIDATE_SUFFIX}")
    update_version_file "${release_version}"
    git add "${VERSION_FILE}"
    git commit -m "[n/a] n/a Release ${release_version} upgrade applied."
    last_commit_message=$(git log --format=%B -n 1)
    git tag -a "v${release_version}" -m "${last_commit_message}"
    git push origin "${current_branch}"
    git push origin --tags
}

function upgrade_release() {
    # Recover data from previous master commits exclusively to analyze previous released version.
    get_last_version_data --first-parent
    # Determine if last commit corresponds to a rc or hotfix merge.
    if [[ ${last_commit_message} == *"${DEVELOP_BRANCH}"* ]] \
        || [[ ${last_commit_message} == *"${RELEASE_CANDIDATE_SUFFIX}"* ]]; then
        # Merge comes from develop or release candidate, remove rc label and preserve version components.
        release_version=$(echo "${version_in_file}")
    elif [[ ${last_commit_message} == *"${HOTFIX_TYPE}"* ]]; then
        # Merge comes from hotfix branch, increment 'Y'
        let version_components[2]++
        release_version=$(echo "${version_components[0]}.${version_components[1]}.${version_components[2]}.${version_components[3]}")
    fi
    update_version_file "${release_version}"
    git add "${VERSION_FILE}"
    git commit -m "[n/a] n/a Release ${release_version} upgrade applied."
    last_commit_message=$(git log --format=%B -n 1)
    git tag -a "v${release_version}" -m "${last_commit_message}"
    git push origin "${current_branch}"
    git push origin --tags
}


function upgrade_version() {
    # Number of commits since last tag
    commits_since_last_tag=$(git describe --long| grep -oP '\d+(?=\-[\w\d]{8}$)')
    if [ ${commits_since_last_tag} -eq 0 ]; then
        echo "No changes since last version. Aborting upgrade."
        exit 1
    fi
    if [[ "${current_branch}" == *"${RELEASE_CANDIDATE_SUFFIX}"* ]]; then
      upgrade_release_candidate
    elif [ "${current_branch}" == ${MASTER_BRANCH} ]; then
      upgrade_release
    fi
}

function calculate_version(){
    types_since_last_tag=($(git log --reverse -n "${commits_since_last_tag}" --format=%B | grep -oP '(?<=\]\s)[\w\/]+(?=\s)'))
    for last_commit_type in "${types_since_last_tag[@]}"
    do :
        if [ ${last_commit_type} == ${FIX_TYPE} ] || [ ${last_commit_type} == ${HOTFIX_TYPE} ]; then
            # Increase version 'Y' component with each bug fix. Reset 'Z' to zero
            let version_components[2]++
            let version_components[3]=0
        elif [ ${last_commit_type} == ${IMPROVEMENT_TYPE} ] || [ ${last_commit_type} == ${GENERIC_TYPE} ]; then
            # Increase version 'Z' component with each improvement.
            let version_components[3]++
        elif [ ${last_commit_type} == ${FEATURE_TYPE} ]; then
            # New features should not be allowed in release branches.
            echo "Commits associated to new functionality should not be applied to release branches." >&2
            echo "Aborting release upgrade." >&2
            exit 1
        else
            # Reject any other commit format.
            echo "Found incorrect syntax in commit messages since last version tag. Please review commit messages structure." >&2
            echo "Aborting release upgrade." >&2
            exit 1
        fi
    done
}

function main() {
    #  Exit immediately if a command exits with a non-zero status.
    # set -e
    # Command options.
    option="${1}"
    message="${2}"

    validate_arguments "$@"

    if [ ${option} == "-c" ]; then
        create_release_candidate "${message}"
    elif [ ${option} == "-u" ]; then
        upgrade_version
    fi

    return 0
}

main "$@"
