#!/bin/sh

########
### This script will query users from AD and import them into OC
########

##      Environment variable declaration

source config/config.cfg

declare -a ad_usr_grp
declare ad_usr_display_name
declare ad_usr_email_address
declare ad_usr
declare oc_usr
declare oc_usr_display_name
declare oc_usr_email_address
declare -a oc_usr_grp

# ${ad_group_user_data_path}/
# ${cloud_user_data_path}

function Check_OC_Group {
    local adUser="$1"
#    local adUserGrp=( $(echo "$2") )
    local group_check=0
    
    awk -F ":" '$1 == "'OCGroup'" {print $2}' "${cloud_user_data_path}/${adUser}"  > "${tmp_path}/oc_usr_grp.lst"   # Fetch OC user's Groups
    while read line
    do
        oc_usr_grp+=("$line")
    done < ${tmp_path}/oc_usr_grp.lst
    
    #   Remove oc_usr_grp.lst to avoid confilict
    rm -f "${tmp_path}/oc_usr_grp.lst"
    if [ -f "${tmp_path}/oc_usr_grp.lst" ]
    then 
        exit 0
    fi
    
    for i in "${oc_usr_grp[@]}" # Check each user's groups in OC against user's group in AD to
                                # find from which group an user is removed.
    do
        group_check=0
        
        for j in "${ad_usr_grp[@]}"
        do
            if [ "${i}" = "${j}" ]
            then
                group_check=1
            fi
        done
        
        if [ $group_check -eq 0 ]
        then
            #   echo "${i} ---- ${adUser}"
            #   Removing users from groups in OC that they are no longer member of in AD
            cmd="su -s /bin/sh apache -c '${php_path} ${cloud_path}/occ group:removeuser \"${i}\" ${adUser}'"
            eval $cmd
        fi
    done
    
    for i in "${ad_usr_grp[@]}"
    do
        group_check=0
        
        for j in "${oc_usr_grp[@]}"
        do
            if [ "${i}" = "${j}" ]
            then
                group_check=1
            fi
        done
        
        if [ $group_check -eq 0 ]
        then
            #   echo "${i} ---- ${adUser}"
            #   Adding users to the groups in OC that they recently become member of in AD
            cmd="su -s /bin/sh apache -c '${php_path} ${cloud_path}/occ group:adduser \"${i}\" ${adUser}'"
            eval $cmd
        fi
    done
    unset oc_usr_grp
}

function Add_OC_User {
    local adUser="$1"
    local adUserDispN="$2"
    local adUserEmAddr="$3"
#    local adUserGrp=( $(echo "$4") )
    local occGroups=''
    for i in "${ad_usr_grp[@]}"
    do
        occGroups="${occGroups} --group=\"${i}\" "
    done
    cleanName=`echo -n ${adUserDispN} | sed -e "s}'} }g"`
    cmd="su -s /bin/sh apache -c '${php_path} ${cloud_path}/occ user:add --password-from-env ${adUser} ${occGroups} --display-name=\"${cleanName}\"'"
    eval $cmd
    cmd="${mysql_path} -D ${cloud_db_name} -u ${cloud_db_user} -p${cloud_db_pass} -s -e \"INSERT INTO oc_preferences (userid,appid,configkey,configvalue) VALUES ('${adUser}','settings','email','${adUserEmAddr}')\""
    eval $cmd
    #su -s /bin/sh apache -c '${php_path} occ user:add --password-from-env ${adUser} ${occGroups} --display-name="${adUserDispN}"'
}

function Remove_OC_User {
    local ocUser="$1"
    local ocUserDispN="$2"
    local ocUserEmAddr="$3"
    local user_check=0
    for i in "${cloud_exception_users[@]}"
    do
        if [ "${i}" = "${ocUser}" ]
        then
            user_check=1
        fi
    done
    
    if [ $user_check -eq 0 ]
    then
        cmd="su -s /bin/sh apache -c '${php_path} ${cloud_path}/occ user:delete ${ocUser}'"
        eval $cmd
    fi
    user_check=0    
}

if [ ! -d "${tmp_path}" ]
then
    mkdir -p "${tmp_path}"
fi

if [ -d ${ad_group_user_data_path} ]
then
    ls ${ad_group_user_data_path} | while read ad_usr
    do
        ad_usr_display_name=`awk -F ":" '$1 == "'DisplayName'" {print $2}' "${ad_group_user_data_path}/${ad_usr}"`  # Fetch AD user's DisplayName
        ad_usr_email_address=`awk -F ":" '$1 == "'EmailAddress'" {print $2}' "${ad_group_user_data_path}/${ad_usr}"`    # Fetch AD user's EmailAddress
        awk -F ":" '$1 == "'ADGroup'" {print $2}' "${ad_group_user_data_path}/${ad_usr}" > "${tmp_path}/ad_usr_grp.lst" # Fetch AD user's Groups
        while read line
        do
            ad_usr_grp+=("$line")
        done < ${tmp_path}/ad_usr_grp.lst
        
        #   Remove ad_usr_grp.lst to avoid confilict
        rm -f "${tmp_path}/ad_usr_grp.lst"
        if [ -f "${tmp_path}/ad_usr_grp.lst" ]
        then 
            exit 0
        fi
        
        if [ -f "${cloud_user_data_path}/${ad_usr}" ]   ##  AD user exist in OC
        then
            Check_OC_Group "${ad_usr}" ## "$(echo ${ad_usr_grp[@]})"
        else    ##  AD user does not exist in OC
            Add_OC_User "${ad_usr}" "${ad_usr_display_name}" "${ad_usr_email_address}" ## "$(echo ${ad_usr_grp[@]})"
        fi
        
        # Remove ad_usr_grp to avoid confilict
        unset ad_usr_grp
    done
fi

if [ -d ${cloud_user_data_path} ]
then
    ls ${cloud_user_data_path} | while read oc_usr
    do
        oc_usr_display_name=`awk -F ":" '$1 == "'DisplayName'" {print $2}' "${cloud_user_data_path}/${oc_usr}"`  # Fetch AD user's DisplayName
        oc_usr_email_address=`awk -F ":" '$1 == "'EmailAddress'" {print $2}' "${cloud_user_data_path}/${oc_usr}"`    # Fetch AD user's EmailAddress
        awk -F ":" '$1 == "'OCGroup'" {print $2}' "${cloud_user_data_path}/${oc_usr}" > "${tmp_path}/oc_usr_grp.lst" # Fetch AD user's Groups
        while read line
        do
            oc_usr_grp+=("$line")
        done < ${tmp_path}/oc_usr_grp.lst
        
        #   Remove oc_usr_grp.lst to avoid confilict
        rm -f "${tmp_path}/oc_usr_grp.lst"
        if [ -f "${tmp_path}/oc_usr_grp.lst" ]
        then 
            exit 0
        fi
        
        if [ ! -f "${ad_group_user_data_path}/${oc_usr}" ]   ##  OC user exist in AD
        then
            Remove_OC_User "${oc_usr}" "${oc_usr_display_name}" "${oc_usr_email_address}" ## "$(echo ${oc_usr_grp[@]})"
        fi
        
        # Remove ad_usr_grp to avoid confilict
        unset oc_usr_grp
    done
fi
