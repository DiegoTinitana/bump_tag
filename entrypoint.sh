#!/bin/bash

# config
source=${SOURCE:-.}
dryrun=${DRY_RUN:-false}
initial_version=${INITIAL_VERSION:-0.0.0}
tag_context=${TAG_CONTEXT:-repo}
develop="develop"
staging="staging"
master="master"
production="production"
v="v"

cd ${GITHUB_WORKSPACE}/${source}

current_branch=$(git rev-parse --abbrev-ref HEAD)
echo "$current_branch ??"
# fetch tags
git fetch --tags

# get latest tag that looks like a semver (with or without v)
case "$tag_context" in
    *repo*) tag=$(git for-each-ref --sort=-v:refname --count=1 --format '%(refname)' refs/tags/[0-9]*.[0-9]*.[0-9]* refs/tags/v[0-9]*.[0-9]*.[0-9]* | cut -d / -f 3-);;
    *branch*) tag=$(git describe --tags --match "*[v0-9].*[0-9\.]" --abbrev=0);;
    * ) echo "Unrecognised context"; exit 1;;
esac

# if there are none, start tags at INITIAL_VERSION which defaults to 0.0.0
if [ -z "$tag" ]
then
    log=$(git log --pretty='%B')
    tag="$initial_version"
else
    log=$(git log $tag..HEAD --pretty='%B')
fi
# get current commit hash for tag
tag_commit=$(git rev-list -n 1 $tag)
echo "$log <><><<><><><><><><><><><><><><><>"
echo "$tag ??"
tag=$(echo $tag | cut -d'-' -f 1)
first=${tag:0:1}
if [ "$first" == "$v" ]; then
    tag=${tag#?}
fi

# get current commit hash
commit=$(git rev-parse HEAD)
if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping..."
    echo ::set-output name=tag::$tag
    exit 0
fi

# get commit logs and determine home to bump the version
# supports #major, #minor, #patch (anything else will be 'minor')
case "$log" in
    *#major* ) 
        exit 0
        # new=$(semver bump major $tag);
        # part="major"
    ;;
    *#minor* ) 
        echo "minor ??????????????????????????"
        if [ "$current_branch" == "$develop" ]; then
            sha=$(git rev-parse --short ${commit})
            new=$(semver bump minor $tag);
            new="$new-$sha" 
            part="minor"
        fi
    ;;
    *#patch* )
        echo "patch ??????????????????????????"
        if [ "$current_branch" == "$develop" ]; then
            sha=$(git rev-parse --short ${commit})
            new=$(semver bump patch $tag);
            new="$new-$sha" 
            part="patch"
         fi
    ;;
esac
echo "$part <<<<<<<<<<<<"

case "$current_branch" in
    *staging* ) 
        new="$tag-stg"
    ;;
    *master* )
        build_number=$(git tag | grep "rc" | wc -l)
        build_number=$((build_number+1))
        echo "$build_number"
        new="$tag-rc$build_number"
    ;;
    *production* )
        new="v$tag"
    ;;
esac

# set outputs
echo ::set-output name=new_tag::$new
echo ::set-output name=part::$part

# use dry run to determine the next tag
if $dryrun
then
    echo ::set-output name=tag::$tag
    exit 0
fi 

echo ::set-output name=tag::$new

# push new tag ref to github
dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
full_name=$GITHUB_REPOSITORY
git_refs_url=$(jq .repository.git_refs_url $GITHUB_EVENT_PATH | tr -d '"' | sed 's/{\/sha}//g')

echo "$dt: **pushing tag $new to repo $full_name"

curl -s -X POST $git_refs_url \
-H "Authorization: token $GITHUB_TOKEN" \
-d @- << EOF

{
  "ref": "refs/tags/$new",
  "sha": "$commit"
}
EOF
