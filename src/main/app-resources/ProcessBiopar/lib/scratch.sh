#URL="https://catalogue.nextgeoss.eu/opensearch/search.atom?productType=SENTINEL2_L1C&timerange_start=2020-01-01&timerange_end=2020-08-01&bbox=2.99971768449,49.5548000573,4.51786312754,50.5522921106&count=19&identifier=S2B_MSIL1C_20180705T105029_N0206_R051_T31UFS_20180705T143710"
#URL="https://catalogue.nextgeoss.eu/opensearch/search.atom?productType=SENTINEL2_L1C&timerange_start=2019-01-01&timerange_end=2019-01-02&bbox=-4.130859375,46.558860303117164,12.041015625,54.265224078605684&count=54&identifier=S2B_MSIL1C_20190101T105439_N0207_R051_T31UES_20190101T125038"
#URL="https://catalogue.nextgeoss.eu/opensearch/search.atom?productType=SENTINEL2_L1C&q=&sort=%22score%20desc,%20metadata_modified%20desc%22&bbox=-4.130859375,46.558860303117164,12.041015625,54.265224078605684&ext_prev_extent=-30.520019531249996,49.809631563563094,-4.81201171875,55.15376626853556&timerange_start=2020-03-12&timerange_end=2020-03-13"

URL="http://catalogue-lite.nextgeoss.eu/opensearch/search.atom?productType=SENTINEL2_L1C&timerange_start=2020-05-22&timerange_end=2020-05-23&bbox=4.1748046875,51.11128208389564,5.78155517578125,51.45486265825492&count=3&identifier=S2B_MSIL1C_20200522T103629_N0209_R008_T31UFT_20200522T133046"

function getosparams() {
        URL=$1	
	PARAMS=${URL##*\?}
	PARAMS_ARR=(${PARAMS//[&]/ })
	declare -A PARAM_MAPPING
	PARAM_MAPPING['identifier']="{http://a9.com/-/opensearch/extensions/geo/1.0/}uid"
	PARAM_MAPPING['timerange_start']="{http://a9.com/-/opensearch/extensions/time/1.0/}start"
	PARAM_MAPPING['timerange_end']="{http://a9.com/-/opensearch/extensions/time/1.0/}end"
	PARAM_MAPPING['bbox']="{http://a9.com/-/opensearch/extensions/geo/1.0/}box"
	PARAM_MAPPING['count']="{http://a9.com/-/spec/opensearch/1.1/}count"

	COMMAND_PARAMS=""
	for param in "${PARAMS_ARR[@]}"
	do
		p=(${param//[=]/ })

		if [[ ! -z ${PARAM_MAPPING[${p[0]}]} ]]; then
			COMMAND_PARAMS+=" -p ${PARAM_MAPPING[${p[0]}]}=${p[1]}"
		fi	
	done
	echo $COMMAND_PARAMS

}

echo "$URL"

INPUT_DIR='/tmp/s2-biopar-input'

mkdir -p $INPUT_DIR

PARAMS=$(getosparams $URL)
echo "opensearch-client $PARAMS https://catalogue-lite.nextgeoss.eu/opensearch/description.xml?osdd=SENTINEL2_L1C enclosure" > commands.log

for enclosure in $(opensearch-client $PARAMS https://catalogue-lite.nextgeoss.eu/opensearch/description.xml?osdd=SENTINEL2_L1C enclosure); 
do
	echo "Start 2 copy enclosure ${enclosure}"
        # Copy file to given input directory
	echo "ciop-copy -U -o /tmp \"${enclosure}\"" >> commands.log
	echo $enclosure >> enclosure.txt
        s2Product=$(ciop-copy -U -o ${INPUT_DIR} "${enclosure}")
done

echo $s2Product
