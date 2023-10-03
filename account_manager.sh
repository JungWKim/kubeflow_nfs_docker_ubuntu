#!/bin/bash

# This script is for creating, deleting and listing user accounts in kubeflow
# 
# Below things are prerequisite before executing this script
# 1. run as root
# 2. install apache2-utils package to enable hashing passwords
# 3. At least one administrator account must exist also its home directory too. And you have to input the name in USER variable
#
# how it works
# 1. All accounts are recorded in config-map.yaml in dex directory
# 2. every account's email format is united as '@example.com'. For example, if you created one account whose name is 'admin', its email will be 'admin@example.com' automatically.

USER=

func_prerequisite() {

	# root user check
	if [ "${UID}" -ne 0 ] ; then
                echo -e " You're not running the scipt as root. Please check your clearance."
                exit 1
	fi

	# check USER variable is defined
	if [ -z "$USER" ] ; then
		echo -e " USER variable is not defined."
		echo -e " Please write value in USER."
		exit 1 ; fi

	# define HOME directory
	if [ $USER = root ] ; then
		USER_HOME=/root
	else
		USER_HOME=/home/$USER ; fi

	# check USER_HOME directory exists
	if [ ! -d $USER_HOME ] ; then
		echo -e "user home directory doesn't exist."
		exit 1 ; fi
	
	# check htpasswd is installed
	if [ ! -e /usr/bin/htpasswd ] ; then
		echo -e "htpasswd doesn't exist. Enter 'sudo apt install -y apache2-utils'"
		exit 1 ; fi

	# check manifests directory exists
	if [ ! -d $USER_HOME/manifests ] ; then
		echo -e "manifests directory doesn't exist."
		exit 1; fi
}

# display how to use this script
func_usage() {
	echo "  a  add user"
	echo "  d  delete user"
	echo "  l  list users"
	echo "  q  exit this program"
}

func_useradd() {

	local EMAIL NAME
	local PW PW_confirm
	local ENCRYPT_PW

	# input user information
	echo -e "----- New user information -----"
	while [ -z ${NAME} ] ; do
		read -e -p "username: " NAME ; done

	# skip the operation if special characters or blank spaces are found
	if [[ $NAME == "username" || $NAME == "email" || $NAME == *\!* || 
	      $NAME == *\@* || $NAME == *\#* || $NAME == *\$* || $NAME == *\%* ||
	      $NAME == *\^* || $NAME == *\&* || $NAME == *\** || $NAME == *\(* ||
	      $NAME == *\)* || $NAME == *\-* || $NAME == *\_* || $NAME == *\+* ||
	      $NAME == *\=* || $NAME == *\[* || $NAME == *\]* || $NAME == *\{* ||
	      $NAME == *\}* || $NAME == *\\* || $NAME == *\|* || $NAME == *\;* ||
	      $NAME == *\:* || $NAME == *\'* || $NAME == *\"* || $NAME == *\/* ||
	      $NAME == *\?* || $NAME == *\,* || $NAME == *\.* || $NAME == *\<* ||
	      $NAME == *\>* || $NAME == *\`* || $NAME == *\~* || "$NAME" == *\ * ]] ; then
		echo "You can't create an account with $NAME. Please avoid using special charactersor blank space."
	else
		# check $NAME exists
		grep username $USER_HOME/manifests/common/dex/base/config-map.yaml | cut -d ":" -f 2 | grep -x " ${NAME}" 1> /dev/null
		# if it does, do not operate creation
		if [ $? -eq 0 ] ; then
			echo "\"$NAME\" already exist."
		else
			while [ -z "${PW}" ] ; do
				read -s -e -p "password: " PW 
				echo ""
			done
			
			# password confirmation
			while [ -z "${PW_confirm}" ] ; do
				read -s -e -p "password confirmation: " PW_confirm
				echo ""
			done

			# when passwords don't match, exit creation
			if [ ${PW} != ${PW_confirm} ] ; then
				echo "password doesn't match. try again."
			# otherwise, create an account
			else
				EMAIL=${NAME}@example.com
				# bcrypt user's password
				ENCRYPT_PW=$(htpasswd -nbBC 10 $NAME $PW | cut -d ':' -f 2)
				
				# create profile. Then namespace will also be created automatically
				kubectl apply -f - <<EOF
---
apiVersion: kubeflow.org/v1beta1
kind: Profile
metadata:
  name: $NAME
spec:
  owner:
    kind: User
    name: $EMAIL
EOF
				# if problem happens when creating profile, then stop
				if [ $? -ne 0 ] ; then 
					kubectl delete profile ${NAME}

					echo "** New User registration successfully failed **"
				else
					# input new user's information into config-map.yaml
					sed -i -r -e "/staticPasswords/a\    \- email: ${EMAIL}\\n      hash: ${ENCRYPT_PW}\\n      username: ${NAME}\\n      userID: ${NAME}" $USER_HOME/manifests/common/dex/base/config-map.yaml

					# apply changes in config-map.yaml
					kustomize build $USER_HOME/manifests/example | kubectl apply -f - 1> /dev/null

					# restart dex deployment
					kubectl -n auth rollout restart deployment dex

					echo "** New User registration successfully finished **"
				fi
			fi
		fi
	fi
}

func_userdel() {

	local EMAIL NAME ANSWER

	# input user which you want to delete
	echo -e "--- Enter information for deletion ---"
	while [ -z "${NAME}" ] ; do
		read -e -p "Name: " NAME 
	done

	# if the account doesn't exist, do not operate deletion
	grep username $USER_HOME/manifests/common/dex/base/config-map.yaml | cut -d ":" -f 2 | grep -x " ${NAME}" &> /dev/null
	if [ $? -ne 0 ] ; then
		echo "$NAME doesn't exist."
	# otherwise, delete it
	else
		EMAIL=${NAME}@example.com

		# delete user account in config-map.yaml
		sed -i -e "/ ${EMAIL}/,+3 d" $USER_HOME/manifests/common/dex/base/config-map.yaml

		kustomize build $USER_HOME/manifests/example | kubectl apply -f - 1> /dev/null

		# restart dex deployment
		kubectl -n auth rollout restart deployment dex

		# actually delete profile and namespace in k8s
		kubectl delete profile $NAME

		echo "** User ${NAME} is deleted successfully **"
	fi
}

func_list() {
	
	echo ""
	grep username $USER_HOME/manifests/common/dex/base/config-map.yaml | cut -d ':' -f 2 | awk '{print $1}' | sort
}

# check prerequisite things before main operation
func_prerequisite

# main operation
echo -e "\n----- Welcome to kubeflow account manager -----\n"
while true ; do

	read -e -p "Command (m for help) : " OPERATION
	if [ $OPERATION = m ] ; then
		func_usage
		echo ""
	elif [ $OPERATION = a ] ; then
		func_useradd
		echo ""
	elif [ $OPERATION = d ] ; then
		func_userdel
		echo ""
	elif [ $OPERATION = l ] ; then
		func_list
		echo ""
	elif [ $OPERATION = q ] ; then
		echo -e "\nExiting program...\n"
		exit 0
	else
		echo -e "\nWrong input!!"
		echo ""
		continue ; fi
done
