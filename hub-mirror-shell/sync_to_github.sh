#!/bin/bash
# 获取组织下面所有公开仓库
# 清理结果文件
WORKSPACE=/hub-mirror-shell
HEADER='Content-Type: application/json;charset=UTF-8'
gitee_groups=openharmony
github_token=$1
if [ -f ${WORKSPACE}/api_result.txt ];then
    rm -rf ${WORKSPACE}/api_result.txt
fi
curl -I --dump-header ${WORKSPACE}/API.info -s -k -X GET --header "${HEADER}" "https://gitee.com/api/v5/orgs/${gitee_groups}/repos?type=public&page=1&per_page=100"
sleep 1
if [ ! -f ${WORKSPACE}/API.info ];then
    echo "API获取信息失败,请检查API调用"
    exit 1
else
    total_page=`cat ${WORKSPACE}/API.info|grep total_page|awk '{print $NF}'|sed 's/\\r//g'`
    total_count=`cat ${WORKSPACE}/API.info|grep total_count|awk '{print $NF}'|sed 's/\\r//g'`
fi

if [ "X${total_page}" == "X" ];then
    curl -s -k -X GET --header "${HEADER}" "https://gitee.com/api/v5/orgs/${gitee_groups}/repos?type=public&page=1&per_page=100">>${WORKSPACE}/api_result.txt
else
    for(( i = 1; i <= ${total_page}; i = i + 1 ))
    do
        curl -s -k -X GET --header "${HEADER}" "https://gitee.com/api/v5/orgs/${gitee_groups}/repos?type=public&page=${i}&per_page=100" >>${WORKSPACE}/api_result.txt

    done
fi
# Github 仓库是否存在,如果不存在创建出来
function check_github_repo(){
  check_github_repo_repo_name=$1
  # Todo
}

# 处理API结果
cat ${WORKSPACE}/api_result.txt|jq -r .[].name >${WORKSPACE}/jq.name
cat ${WORKSPACE}/api_result.txt|jq .[].description|sed 's/,/|/g;s/"//g;s/\[//g;s/\]//g' >${WORKSPACE}/jq.description
cat ${WORKSPACE}/api_result.txt|jq -r .[].default_branch >${WORKSPACE}/jq.default_branch

paste -d, ${WORKSPACE}/jq.name ${WORKSPACE}/jq.default_branch ${WORKSPACE}/jq.description >${WORKSPACE}/${gitee_groups}_${unix_time}.csv

# 同步代码到GitHub

bare_git_dir=/data01/project-objects
all_num=`cat ${WORKSPACE}/${gitee_groups}_${unix_time}.csv|wc -l`
just_num=0
if [ -f ${WORKSPACE}/github_api.log ];then
   echo ' '>${WORKSPACE}/github_api.log
fi
while read ONE_REPO
do
    just_num=$((just_num+1))
    repo_name=`echo ${ONE_REPO}|awk -F ',' '{print $1}'`
    default_branch=`echo ${ONE_REPO}|awk -F ',' '{print $2}'`
    description=`echo ${ONE_REPO}|awk -F ',' '{print $NF}'`
    if [ "X${description}" == "Xnull" ];then
        description=
    fi
    
    echo "${just_num}/${all_num},deal ${repo_name}"
    echo "${just_num}/${all_num},deal ${repo_name}" >>${WORKSPACE}/github_api.log
    # 不管是否存在,均init
    git init --bare ${bare_git_dir}/${repo_name}.git
    cd ${bare_git_dir}/${repo_name}.git
    git fetch -f git@gitee.com:${gitee_groups}/${repo_name}.git refs/heads/*:refs/heads/*
    git fetch -f git@gitee.com:${gitee_groups}/${repo_name}.git refs/tags/*:refs/tags/*
    git lfs fetch --all git@gitee.com:${gitee_groups}/${repo_name}.git
    echo "git push -f git@github.com:${gitee_groups}/${repo_name}.git refs/heads/*:refs/heads/*"
    echo "git push -f git@github.com:${gitee_groups}/${repo_name}.git refs/tags/*:refs/tags/*"
    echo "git lfs push --all git@github.com:${gitee_groups}/${repo_name}.git"
    # 处理github仓库描述与默认分支
    github_body="{\"description\":\"${description}\",\"default_branch\":\"${default_branch}\"}"
    echo "curl -s -k -H 'Accept: application/vnd.github.v3+json' -X PATCH https://api.github.com/repos/${gitee_groups}/${repo_name}?access_token=${github_token} -d \"${github_body}\" >>${WORKSPACE}/github_api.log"
done<${WORKSPACE}/${gitee_groups}_${unix_time}.csv