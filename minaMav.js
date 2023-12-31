
const requests = require('requests')

let url = "https://graphql.minaexplorer.com"

const LIMIT = 1000

async function getSlice(epoch, blockHeight){
    const query = `query MyQuery {
        blocks(query: {protocolState: {consensusState: {epoch: ${epoch}}}, AND: {blockHeight_gt: ${blockHeight}, AND: {canonical: true}}}, limit: ${LIMIT}, sortBy: BLOCKHEIGHT_ASC) {
          protocolState {
            consensusState {
              epoch
              blockHeight
            }
          }
          creator
        }
      }`
      let response = await fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({query: query})
    });
    
    
    let data = await response.json();
    console.log(data.data.blocks.length, data.data.blocks[0].protocolState.consensusState.blockHeight)
    return data.data.blocks
    
}

async function main(epoch) {
    const blocks = await getSlice(epoch, 0)
    let newBlocks = blocks
    let blockHeight = blocks[blocks.length-1].protocolState.consensusState.blockHeight
    while(newBlocks.length === LIMIT){
        newBlocks = await getSlice(epoch, blockHeight)
        blockHeight = newBlocks[newBlocks.length-1].protocolState.consensusState.blockHeight
        blocks.push(...newBlocks)
    }

    const producers = {}

    blocks.forEach(block => {
        if(producers[block.creator]){
            producers[block.creator] += 1
        } else {
            producers[block.creator] = 1
        }
    })

    let producersArray = Object.entries(producers);

    producersArray.sort((a, b) => b[1] - a[1]);

    let sortedProducers = Object.fromEntries(producersArray);

    console.log(`Mina epoch producers production count : ${JSON.stringify(sortedProducers)}`)
    const totalBlocks = blocks.length
    let mav = 0
    let totalMavCount = 0
    for(let producer in sortedProducers){
        const count = producers[producer]
        mav += 1
        totalMavCount += count
        console.log(`Mina epoch MAV ${mav} : ${producer} : ${count}`)
        if(totalMavCount > totalBlocks/2){
            break
        }
    }

    console.log(`Mina epoch MAV : ${mav}`)
    console.log(`Mina epoch MAV production : ${totalMavCount}`)
    console.log(`Mina epoch producers count : ${Object.keys(producers).length}`)
    console.log(totalBlocks)
}

main(67);