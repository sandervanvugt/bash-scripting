#!/bin/bash
# script for internal use by SvV to distribute changes from master kubernetes
# git repo to all git repos that need the same stuff
# to be executed from the "kubernetes" directory

FILES="Setup\ Guide.pdf Setup\ Guide-AiO.pdf minikube-docker-setup.sh setup-container.sh setup-kubetools-ubuntu.sh"

echo files is set to $FILES
read

REPOS="cka ckad devopsinfourweeks kub4h microservices"
for i in $REPOS
do
	for j in $FILES
	do
		echo ln $j $i/
	done
done

for k in $REPOS
do
	cd ../$k
	echo git add *
	echo git commit -m "automated update"
	echo git push
done
