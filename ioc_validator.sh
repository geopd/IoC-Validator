#!/bin/bash

#
# Copyright (C) 2022 GeoPD <geoemmanuelpd2001@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#Set default API key for virustotal API3, IOC file name and score threshold
APIKEY=
FILE_NAME=ioc.txt
THRESHOLD=5

#Import API key for virustotal API3 and IOC file name
while getopts ":f:k:t:" arg; do
	case $arg in
		f) FILE_NAME="$OPTARG";;
		k) APIKEY="$OPTARG";;
		t) THRESHOLD="$OPTARG";;
		?) echo "Invalid arguments"; exit 1;;
	esac
	IOCS=$(pwd)/"$FILE_NAME"
done


#Defang the IoC in the output csv file
defang() {
	sed -i 's/\./[\.]/g' $OUTPUT
	sed -i 's/http/hxxp/g' $OUTPUT
}


#Fang the IOCs
fang() {
	sed -i 's/[][]//g' $IOCS
	sed -i 's/hxxp/http/g' $IOCS
}


#Regrex patterns for IP, URL, DOMAIN and HASH match.
regrex_patterns() {
	ip_check="(\b25[0-5]|\b2[0-4][0-9]|\b[01]?[0-9][0-9]?)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}"
	url_check="https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)"
	domain_check="(([\da-zA-Z])([_\w-]{,62})\.){,127}(([\da-zA-Z])[_\w-]{,61})?([\da-zA-Z]\.((xn\-\-[a-zA-Z\d]+)|([a-zA-Z\d]{2,})))"
	hash_check="^[A-Fa-f0-9]{32,64}$"
}


#Parse the variable
#Generate .csv result as output
output_generation() {
	mkdir -p $(pwd)/Results
	OUTPUT=$(pwd)/Results/ioc_validation_$(date +"%d%m%Y_%H%M%S").csv
	touch $OUTPUT
}


#Virustotal API V3
virustotal_call(){
	curl -s --request GET \
		--url "https://www.virustotal.com/api/v3/"$1"/"$2"" \
		--header "x-apikey: $APIKEY"
}


#Scrap malicious,harmless,suspicious and undetected scores
analysis_scores() {
	malicious=$(echo $virustotal_out | jq -r '.data.attributes.last_analysis_stats.malicious')
	harmless=$(echo $virustotal_out | jq -r '.data.attributes.last_analysis_stats.harmless')
	suspicious=$(echo $virustotal_out | jq -r '.data.attributes.last_analysis_stats.suspicious')
	undetected=$(echo $virustotal_out | jq -r '.data.attributes.last_analysis_stats.undetected')
}


#Scrap the md5,sha1 and sha256 hashes
multi_shas() {
	md5_out=$(echo $virustotal_out | jq -r '.data.attributes.md5')
	sha1_out=$(echo $virustotal_out | jq -r '.data.attributes.sha1')
	sha256_out=$(echo $virustotal_out | jq -r '.data.attributes.sha256')
}


#Terminal output for users
terminal_output() {
	echo "----------------------------------------------------------------"
	echo $1
	echo "----------------------------------------------------------------"
	echo "VirusTotal:" $2 "out of" $3
	echo ""
}


#IOCS processing for validation
ioc_processing() {
	for i in $(cat $IOCS)
	do
		if [[ $i =~ $url_check ]]; then
			base_value=$(echo $i | base64 -w0 | tr '+/' '-_' | tr -d '=')
			virustotal_out=$(virustotal_call urls $base_value)
			analysis_scores
			terminal_output $i $malicious $(($malicious + $harmless + $suspicious + $undetected))
			if [[ $malicious -ge $THRESHOLD ]]; then
				echo $i "," $malicious "out of" $(($malicious + $harmless + $suspicious + $undetected)) "," "Target is URL" >> $OUTPUT
			fi
		elif [[ $i =~ $domain_check ]]; then
			virustotal_out=$(virustotal_call domains $i)
			analysis_scores
			terminal_output $i $malicious $(($malicious + $harmless + $suspicious + $undetected))
			if [[ $malicious -ge $THRESHOLD ]]; then
				echo $i "," $malicious "out of" $(($malicious + $harmless + $suspicious + $undetected)) "," "Target is DOMAIN" >> $OUTPUT
			fi
		elif [[ $i =~ $ip_check ]]; then
			virustotal_out=$(virustotal_call ip_addresses $i)
			analysis_scores
			terminal_output $i $malicious $(($malicious + $harmless + $suspicious + $undetected))
			if [[ $malicious -ge $THRESHOLD ]]; then
				echo $i "," $malicious "out of" $(($malicious + $harmless + $suspicious + $undetected)) "," "Target is IP Address" >> $OUTPUT
			fi
		elif [[ $i =~ $hash_check ]]; then
			virustotal_out=$(virustotal_call files $i)
			analysis_scores
			multi_shas
			terminal_output $i $malicious $(($malicious + $harmless + $suspicious + $undetected))
			if [[ $malicious -ge $THRESHOLD ]]; then
				echo $i "," $md5_out "," $sha1_out "," $sha256_out "," $malicious "out of" $(($malicious + $harmless + $suspicious + $undetected)) "," "Target is HASH" >> $OUTPUT
			fi
		else
			echo $i >> $OUTPUT
		fi
	done
}


#Final IOC Validation moments
validation_moments() {
	fang
	regrex_patterns
	output_generation
	ioc_processing
	defang
}

validation_moments
