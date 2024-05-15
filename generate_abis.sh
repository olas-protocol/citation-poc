mkdir -p abis
    for f in $(find out -name '*.json'); do
        jq '.abi' $f > "abis/$(basename ${f%.*})_ABI.json"
    done