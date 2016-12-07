#!/bin/sh
# @author Mehrdad Vatanparvar, m.vatanparvar@gmail.com

########
### This script will query users from AD and import them into OC
########

##	Environment variable declaration

source config/config.cfg

##	Declare Active Directory groups that contain users of Nextcloud.
##	GROUP 4 & GROUP 5 have no Email Address in Active Directory
declare -a ad_cn=('GROUP 1' 'GROUP 2' 'GROUP 3' 'GROUP 4' 'GROUP 5')

declare -a ad_user_data

mkdir -p ${cloud_user_data_path}

ad_cn_len=${#ad_cn[@]}

##	Query Active Dirctory for users info (mail, sAMAccountName and cn)
mkdir -p "${ad_group_user_data_path}"

for i in "${ad_cn[@]}"
do
	cn="CN="${i}","
	#cleanName=`echo -n ${i} | sed -e "s}[/\!\"'£$%^&*()+=]}-}g" -e 's/[[:space:]]//g'`
	if [ "${i}" = "GROUP 4" -o "${i}" = "GROUP 5" ]
	then
        cmd="/bin/ldapsearch  -x -LLL -h  \"${ad_host}\" -D \"${ad_admin}\" -w ${ad_pass} -b \"${ad_base}\" -s sub \"${ad_filter_1}${cn}${ad_filter_2}\" sAMAccountName cn | /bin/grep -e \"${grep_filter_2}:\" -e \"${grep_filter_3}:\""
	else
        cmd="/bin/ldapsearch  -x -LLL -h  \"${ad_host}\" -D \"${ad_admin}\" -w ${ad_pass} -b \"${ad_base}\" -s sub \"${ad_filter_1}${cn}${ad_filter_2}\" sAMAccountName mail cn | /bin/grep -e \"${grep_filter_1}:\" -e \"${grep_filter_2}:\" -e \"${grep_filter_3}:\""
    fi
	#mkdir -p "${ad_group_user_data_path}/${i}"

	counter=0
	while read line
	do
        if [ "${i}" = "GROUP 4" -o "${i}" = "GROUP 5" ]
        then
            case "${counter}" in
            "0")
                ad_user_data[0]=`echo -n ${line} | awk -F ": " '$1 == "'${grep_filter_3}'" {print $2}'`
                counter=1
            ;;
            "1")
                ad_user_data[1]=`echo -n ${line} | awk -F ": " '$1 == "'${grep_filter_2}'" {print $2}'`
                counter=0
                if [ -f "${ad_group_user_data_path}/${ad_user_data[1]}" ]
                then
                    echo "ADGroup:${i}" >> "${ad_group_user_data_path}/${ad_user_data[1]}"
                else
                    touch "${ad_group_user_data_path}/${ad_user_data[1]}"
                    echo "DisplayName:${ad_user_data[0]}" > "${ad_group_user_data_path}/${ad_user_data[1]}"
                    echo "EmailAddress:" >> "${ad_group_user_data_path}/${ad_user_data[1]}"
                    echo "ADGroup:${i}" >> "${ad_group_user_data_path}/${ad_user_data[1]}"
                    echo "ADGroup:NextcloudUsers" >> "${ad_group_user_data_path}/${ad_user_data[1]}"
                fi
            ;;
            esac
        else
            case "${counter}" in
            "0")
                ad_user_data[0]=`echo -n ${line} | awk -F ": " '$1 == "'${grep_filter_3}'" {print $2}'`
                counter=1
            ;;
            "1")
                ad_user_data[1]=`echo -n ${line} | awk -F ": " '$1 == "'${grep_filter_2}'" {print $2}'`
                counter=2
            ;;
            "2")
                ad_user_data[2]=`echo -n ${line} | awk -F ": " '$1 == "'${grep_filter_1}'" {print $2}'`
                counter=0
                if [ -f "${ad_group_user_data_path}/${ad_user_data[1]}" ]
                then
                    echo "ADGroup:${i}" >> "${ad_group_user_data_path}/${ad_user_data[1]}"
                else
                    touch "${ad_group_user_data_path}/${ad_user_data[1]}"
                    echo "DisplayName:${ad_user_data[0]}" > "${ad_group_user_data_path}/${ad_user_data[1]}"
                    echo "EmailAddress:${ad_user_data[2]}" >> "${ad_group_user_data_path}/${ad_user_data[1]}"
                    echo "ADGroup:${i}" >> "${ad_group_user_data_path}/${ad_user_data[1]}"
                    echo "ADGroup:NextcloudUsers" >> "${ad_group_user_data_path}/${ad_user_data[1]}"
                fi
            ;;
            esac
        fi
	done <<< "`eval $cmd`"
done

##	Query Cloud database to extract user list and groups they belong to

cmd="${mysql_path} -D ${cloud_db_name} -u ${cloud_db_user} -p${cloud_db_pass} -s -e \"SELECT uid FROM oc_users\""
while read -r line
do
    cloud_users+=("$line")
done <<< "`eval $cmd`"

for i in "${cloud_users[@]}"
do
    cmd="${mysql_path} -D ${cloud_db_name} -u ${cloud_db_user} -p${cloud_db_pass} -s -e \"SELECT gid FROM oc_group_user WHERE uid='${i}'\""
    touch "${cloud_user_data_path}/${i}"
    while read -r line
    do
        echo "OCGroup:${line}" >> "${cloud_user_data_path}/${i}"
        
    done <<< "`eval $cmd`"
    cmd="${mysql_path} -D ${cloud_db_name} -u ${cloud_db_user} -p${cloud_db_pass} -s -e \"SELECT displayname FROM oc_users WHERE uid = '${i}'\""
    echo "DisplayName:`eval $cmd`" >> "${cloud_user_data_path}/${i}"
    cmd="${mysql_path} -D ${cloud_db_name} -u ${cloud_db_user} -p${cloud_db_pass} -s -e \"SELECT configvalue FROM oc_preferences WHERE userid = '${i}' AND configkey = 'email'\""
    echo "EmailAddress:`eval $cmd`" >> "${cloud_user_data_path}/${i}"
done

