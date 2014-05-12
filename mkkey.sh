#!/bin/bash
#AUTH='/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/emailAddress=swpark@nexell.co.kr'
AUTH='/CN=Android/'
if [ "$1" == "" ] || [ "$2" == "" ]; then
    echo "Create a test certificate key."
    echo "Usage: $0 NAME BoardName"
    echo "Will generate NAME.pk8 and NAME.x509.pem"
    echo "  $AUTH"
    exit
fi

NAME=$1
DIR=vendor/nexell/security/$2

mkdir -p ${DIR}

openssl genrsa -3 -out ${DIR}/${NAME}.pem 2048

openssl req -new -x509 -sha1 -key ${DIR}/${NAME}.pem -out ${DIR}/${NAME}.x509.pem -days 10000 -subj "$AUTH"

openssl pkcs8 -in ${DIR}/${NAME}.pem -topk8 -outform DER -out ${DIR}/${NAME}.pk8 -nocrypt

#development/tools/make_key ${DIR}/${NAME} ${AUTH}
