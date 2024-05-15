const fs = require('fs').promises;
const path = require('path');

// Read and extract ABI from JSON files
async function extractABIs(srcPath, outDir, abisDir) {
    const fileName = path.basename(srcPath, '.sol');
    // srcPath: src/MyContract.sol
    // outDir:  out/MyContract.sol
    // jsonDir: out/MyContract.sol/MyContract.json
    const jsonDir = path.join(outDir, `${fileName}.sol`);
    const jsonPath = path.join(jsonDir, `${fileName}.json`);

    try {
        const jsonData = await fs.readFile(jsonPath, 'utf8');
        const data = JSON.parse(jsonData);
        if (data.abi) {
            const abiPath = path.join(abisDir, `${fileName}_ABI.json`);
            await fs.writeFile(abiPath, JSON.stringify(data.abi, null, 2));
            console.log(`ABI saved to ${abiPath}`);
        } else {
            console.log(`No ABI found in ${jsonPath}`);
        }
    } catch (error) {
        console.error(`Error processing ABI for ${fileName}:`, error);
    }
}

// Recursively get contract names from the src directory
async function getContractNames(directory) {
    let files = [];
    try {
        const items = await fs.readdir(directory, { withFileTypes: true });
        for (const item of items) {
            const itemPath = path.join(directory, item.name);
            if (item.isDirectory()) {
                const subDirFiles = await getContractNames(itemPath);
                files = files.concat(subDirFiles);
            } else if (item.isFile() && item.name.endsWith('.sol')) {
                files.push(itemPath);
            }
        }
    } catch (error) {
        console.error(`Error reading files from ${directory}:`, error);
    }
    return files;
}

async function processFiles() {
    // Define the directories
    const srcDir = path.resolve(__dirname, '..', 'src');
    const outDir = path.resolve(__dirname, '..', 'out');
    const abisDir = path.join(srcDir, 'abis');

    // Check if the 'out' directory exists
    try {
        await fs.access(outDir);
    } catch (error) {
        console.error("The 'out' directory does not exist. Run 'forge build' before proceeding.");
        return;
    }

    // Create the output directory if it doesn't exist
    await fs.mkdir(abisDir, { recursive: true });

    try {
        const contracts = await getContractNames(srcDir);
        for (const contract of contracts) {
            await extractABIs(contract, outDir, abisDir);
        }
    } catch (error) {
        console.error(`Error in processing files: ${error}`);
    }
}

processFiles();
