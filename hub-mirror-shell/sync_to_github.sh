#!/bin/bash
github_token=$1
debug_type=`echo $2|tr 'a-z' 'A-Z'`
gitee_groups=`echo $3|sed 's#gitee/##g'`
github_groups=`echo $4|sed 's#github/##g'`

WORKSPACE=$5
if [ "X${debug_type}" == "XTRUE" ];then
  set -x
else
  set +x
fi
set -x
# 获取组织下面所有公开仓库
# 清理结果文件

HEADER='Content-Type: application/json;charset=UTF-8'
unix_time=`date '+%s'`

author_header="Authorization:token ${github_token}"
if [ ! -d ${WORKSPACE} ];then mkdir -p ${WORKSPACE};fi
if [ -f ${WORKSPACE}/api_result.txt ];then
    rm -rf ${WORKSPACE}/api_result.txt
fi
curl --connect-timeout 15 -m 600 -I --dump-header ${WORKSPACE}/API.info -s -k -X GET --header "${HEADER}" "https://gitee.com/api/v5/orgs/${gitee_groups}/repos?type=public&page=1&per_page=100" >/dev/null 2>&1
sleep 1
if [ ! -f ${WORKSPACE}/API.info ];then
    echo "API获取信息失败,请检查API调用"
    exit 1
else
    total_page=`cat ${WORKSPACE}/API.info|grep total_page|awk '{print $NF}'|sed 's/\\r//g'`
    total_count=`cat ${WORKSPACE}/API.info|grep total_count|awk '{print $NF}'|sed 's/\\r//g'`
fi

if [ "X${total_page}" == "X" ];then
    curl  --connect-timeout 15 -m 600 -s -k -X GET --header "${HEADER}" "https://gitee.com/api/v5/orgs/${gitee_groups}/repos?type=public&page=1&per_page=100">>${WORKSPACE}/api_result.txt
else
    for(( i = 1; i <= ${total_page}; i = i + 1 ))
    do
        curl  --connect-timeout 15 -m 600 -s -k -X GET --header "${HEADER}" "https://gitee.com/api/v5/orgs/${gitee_groups}/repos?type=public&page=${i}&per_page=100" >>${WORKSPACE}/api_result.txt

    done
fi
# Github 仓库是否存在,如果不存在创建出来
function check_github_repo(){
  check_github_repo_repo_name=$1
  check_github_repo_repo_description=$2
  create_github_project_body="{\"name\":\"${check_github_repo_repo_name}\",\"description\":\"${check_github_repo_repo_description}\",\"private\": false}"
  # 确认仓库是否存在
  git ls-remote git@github.com:${github_groups}/${check_github_repo_repo_name} >/dev/null 2>&1
  if [ $? -gt 0 ];then
     echo  "https://github.com/${github_groups}/${check_github_repo_repo_name} not exist,will create it!"
     curl  --connect-timeout 15 -m 600 -s -k  -H "${author_header}" -H 'Accept: application/vnd.github.v3+json' -X POST -d "${create_github_project_body}" "https://api.github.com/orgs/${github_groups}/repos" >>${WORKSPACE}/github_api.log
  else
     echo "https://github.com/${github_groups}/${check_github_repo_repo_name} exist,continue!"
     # 如果github已存在, 从github fetch一次,用于加速同步
     cd ${bare_git_dir}/${repo_name}.git
     max_retry=10
     for((i=1;i<=${max_retry};i++));
     do
        timeout_num=$((120*$i))
        echo "Fetching refs/heads/* from github:(${i}/${max_retry})"
        timeout ${timeout_num} git fetch -f git@github.com:${github_groups}/${repo_name}.git refs/heads/*:refs/heads/*   >/dev/null
        timeout ${timeout_num} git fetch -f git@github.com:${github_groups}/${repo_name}.git refs/tags/*:refs/tags/*   >/dev/null
        if [ $? -eq 0 ];then i=999;fi
     done
  fi
  # Todo
}

# 处理API结果
cat ${WORKSPACE}/api_result.txt|jq -r .[].name >${WORKSPACE}/jq.name
cat ${WORKSPACE}/api_result.txt|jq .[].description|sed 's/,/|/g;s/"//g;s/\[//g;s/\]//g' >${WORKSPACE}/jq.description
cat ${WORKSPACE}/api_result.txt|jq -r .[].default_branch >${WORKSPACE}/jq.default_branch

paste -d, ${WORKSPACE}/jq.name ${WORKSPACE}/jq.default_branch ${WORKSPACE}/jq.description >${WORKSPACE}/${gitee_groups}_${unix_time}.csv

# 同步代码到GitHub

bare_git_dir=${WORKSPACE}/project-objects
all_num=`cat ${WORKSPACE}/${gitee_groups}_${unix_time}.csv|wc -l`
just_num=0
if [ -f ${WORKSPACE}/github_api.log ];then
   echo ' '>${WORKSPACE}/github_api.log
fi
# 为了debug cache,写死只同步3个仓库
#echo '''community,master,OpenHarmony community governance| developer contribution guide| contribution agreement| and community communication | 包含OpenHarmony社区治理、开发者贡献指南、开发者贡献协议、社区交流等内容
#docs,master,OpenHarmony documentation | OpenHarmony开发者文档
#hiviewdfx_hilog_lite,master,MCU log module in the DFX subsystem | DFX-MCU日志模块'''>${WORKSPACE}/${gitee_groups}_${unix_time}.csv



while read ONE_REPO
do
    just_num=$((just_num+1))
    repo_name=`echo ${ONE_REPO}|awk -F ',' '{print $1}'`
    default_branch=`echo ${ONE_REPO}|awk -F ',' '{print $2}'`
    description=`echo ${ONE_REPO}|awk -F ',' '{print $NF}'`
    if [ "X${description}" == "Xnull" ];then
        description=
    fi
    # 不管本地目录是否存在,均init
    if [ ! -d ${bare_git_dir}/${repo_name}.git ];then
        echo  "Git dir not exist, will init! ${bare_git_dir}/${repo_name}.git"
    else
        echo  "Git dir exist,${bare_git_dir}/${repo_name}.git"
    fi
    git init --bare ${bare_git_dir}/${repo_name}.git
    # 判断Github仓库是否存在,如果不存在创建,如果存在,将会先从github fetch一次
    check_github_repo "${repo_name}" "${description}"
    echo "${just_num}/${all_num},deal ${repo_name}"
    echo "${just_num}/${all_num},deal ${repo_name}" >>${WORKSPACE}/github_api.log
    
    cd ${bare_git_dir}/${repo_name}.git
    max_retry=10
    # 超大仓库特殊处理, 当前仅处理kernel_linux kernel_Linux_4.19 kernei_linux_5.10三个仓库
    # 为防止部分匹配,关键字后加英文逗号
    big_project_lists='''kernel_linux_4.19,torvalds/linux,refs/tags/v4.19
    kernel_linux_5.10,torvalds/linux,refs/tags/v5.10
    kernel_linux,torvalds/linux,refs/tags/v4.19'''
    big_project_info=`echo "${big_project_lists// /}"|grep -E "^${repo_name}"|head -n1`
    if [ "X${big_project_info}" != "X" ];then
        github_reponame=`echo ${big_project_info}|awk -F ',' '{print $2}'`
        github_reporefs=`echo ${big_project_info}|awk -F ',' '{print $3}'`
        echo "${repo_name} is big project, fetch from github first!"
        
        for((i=1;i<=${max_retry};i++));
        do
            timeout_num=$((300*$i))
            echo "Fetching from git@github.com:${github_reponame},${github_reporefs}:(${i}/${max_retry})"
            timeout ${timeout_num} git fetch -f git@github.com:${github_reponame}.git ${github_reporefs}:${github_reporefs}   >/dev/null
            if [ $? -eq 0 ];then i=999;fi
        done
    fi
    for((i=1;i<=${max_retry};i++));
    do
        timeout_num=$((120*$i))
        echo "Fetching refs/heads/* from gitee:(${i}/${max_retry})"
        timeout ${timeout_num} git fetch -f git@gitee.com:${gitee_groups}/${repo_name}.git refs/heads/*:refs/heads/*   >/dev/null
        if [ $? -eq 0 ];then i=999;fi
    done
    for((i=1;i<=${max_retry};i++));
    do
        timeout_num=$((120*$i))
        echo "Fetching refs/tags/* from gitee:(${i}/${max_retry})"
        timeout ${timeout_num} git fetch -f git@gitee.com:${gitee_groups}/${repo_name}.git refs/tags/*:refs/tags/*   >/dev/null
        if [ $? -eq 0 ];then i=999;fi
    done
    for((i=1;i<=${max_retry};i++));
    do
        timeout_num=$((120*$i))
        echo "Fetching LFS from gitee:(${i}/${max_retry})"
        timeout ${timeout_num} git lfs fetch --all git@gitee.com:${gitee_groups}/${repo_name}.git   >/dev/null
        if [ $? -eq 0 ];then i=999;fi
    done
    max_retry=3
    for((i=1;i<=${max_retry};i++));
    do
        timeout_num=$((120*$i))
        echo "Push refs/heads/* to Github:(${i}/${max_retry})"
        timeout ${timeout_num} git push -f git@github.com:${github_groups}/${repo_name}.git refs/heads/*:refs/heads/*   >/dev/null
        if [ $? -eq 0 ];then i=999;fi
    done

    for((i=1;i<=${max_retry};i++));
    do
        timeout_num=$((120*$i))
        echo "Push refs/tags/* to Github:(${i}/${max_retry})"
        timeout ${timeout_num} git push -f git@github.com:${github_groups}/${repo_name}.git refs/tags/*:refs/tags/*   >/dev/null
        if [ $? -eq 0 ];then i=999;fi
    done
    for((i=1;i<=${max_retry};i++));
    do
        timeout_num=$((120*$i))
        echo "Push LFS to Github :(${i}/${max_retry})"
        timeout ${timeout_num} git lfs push --all git@github.com:${github_groups}/${repo_name}.git   >/dev/null
        if [ $? -eq 0 ];then i=999;fi
    done

    # 处理github仓库描述与默认分支
    github_des_body="{\"description\":\"${description}\",\"default_branch\":\"${default_branch}\"}"
    curl  --connect-timeout 15 -m 600 -s -k  -H "${author_header}" -H 'Accept: application/vnd.github.v3+json' -X PATCH https://api.github.com/repos/${github_groups}/${repo_name} -d "${github_des_body}" >>${WORKSPACE}/github_api.log

done<${WORKSPACE}/${gitee_groups}_${unix_time}.csv
