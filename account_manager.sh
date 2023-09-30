# This script is for creating, deleting and listing user accounts in kubeflow
# and is available for kubeflow v1.5, v1.6, v1.7
# 
# Below things are prerequisite before executing this script
# 1. run as root
# 2. install apache2-utils package to enable hashing passwords
# 3. At least one administrator account must exist also its home directory too. And you have to input the name in USER variable
# 4. All accounts will be recorded in $HOME/profile.yaml so please check if you have an existing one not to be overwritten
#
# how it works
# 1. UI is designed to be as similar as possible with fdisk command 
# 2. All accounts are recorded in $HOME/profile.yaml and config-map.yaml in dex directory
# 3. every account's email format is united as '@example.com'. For example, if you created one account whose name is 'admin', its email will be 'admin@example.com' automatically.

#!/bin/bash

USER=

func_prerequisite() {

	# root user check
	if [ "${UID}" -ne 0 ] ; then
                echo -e " You're not running the scipt as root. Please check your clearance."
                exit 1
	fi

	# check USER variable is defined
	if [ -z $USER ] ; then
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

	# check $HOME/profile.yaml exists
	if [ ! -e $USER_HOME/profile.yaml ] ; then
		touch $USER_HOME/profile.yaml ; fi

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

	# skip the operation when NAME matches 'username', or 'email'
	if [[ $NAME == "username" || $NAME == "email" ]] ; then
		echo "You can't create an account with $NAME."
		exit 1
	fi

	# check $NAME exists
	grep username $USER_HOME/manifests/common/dex/base/config-map.yaml | grep ${NAME} 1> /dev/null
	# if it does, do not operate creation
	if [ $? -eq 0 ] ; then
		echo "\"$NAME\" already exist."
	# otherwise, operate creation
	else
		while [ -z ${PW} ] ; do
			stty -echo
			read -e -p "password: " PW 
			stty echo
			echo ""
		done
		
		# password confirmation
		while [ -z ${PW_confirm} ] ; do
			stty -echo
			read -e -p "password confirmation: " PW_confirm
			stty echo
			echo ""
		done

		if [ ${PW} != ${PW_confirm} ] ; then
			echo "password doesn't match. try again."
			exit 1
		fi

		EMAIL=${NAME}@example.com
		# bcrypt user's password
		ENCRYPT_PW=$(htpasswd -nbBC 10 $NAME $PW | cut -d ':' -f 2)
		# input new user's information into config-map.yaml
		sed -i -r -e "/staticPasswords/a\    \- email: ${EMAIL}\\n      hash: ${ENCRYPT_PW}\\n      username: ${NAME}\\n      userID: ${NAME}" $USER_HOME/manifests/common/dex/base/config-map.yaml

		# input new user's information into profile.yaml
		cat >> $USER_HOME/profile.yaml <<EOF
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

		# apply changes in config-map.yaml
		kustomize build $USER_HOME/manifests/example | awk '!/well-defined/' | kubectl apply -f - 1> /dev/null

		# create profile following profile.yaml, then it will automatically create namespace
		kubectl apply -f $USER_HOME/profile.yaml

		# restart dex deployment
		kubectl -n auth rollout restart deployment dex

		echo "** New User registration successfully finished **"
	fi
}

func_userdel() {

	local EMAIL NAME ANSWER

	# input user to be deleted
	echo -e "--- Enter information for deletion ---"
	while [ -z ${NAME} ] ; do
		read -e -p "Name: " NAME 
	done

	# check $NAME exists
	# if it doesn't, do not operate deletion
	grep username $USER_HOME/manifests/common/dex/base/config-map.yaml | grep ${NAME} &> /dev/null
	if [ $? -ne 0 ] ; then
		echo "$NAME doesn't exist."
	# if it exists, delete it
	else
		EMAIL=${NAME}@example.com

		# delete user account in config-map.yaml based on email && apply the change
		sed -i -e "/${EMAIL}/,+3 d" $USER_HOME/manifests/common/dex/base/config-map.yaml
		kustomize build $USER_HOME/manifests/example | awk '!/well-defined/' | kubectl apply -f - 1> /dev/null

		# restart dex deployment
		kubectl -n auth rollout restart deployment dex

		# delete user account in profile.yaml based on email
		END=$(grep -n ${EMAIL} $USER_HOME/profile.yaml | cut -d ':' -f 1)
		START=$(expr ${END} - 8)
		if [ $START -lt 0 ] ; then
			START=0 ; fi
		sed -i "${START},${END} d" $USER_HOME/profile.yaml

		# actually delete profile and namespace in k8s
		kubectl delete profile $NAME
		kubectl delete ns $NAME

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
