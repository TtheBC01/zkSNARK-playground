## Part 1: Setting up your Docker environment

This tutorial assumes you have Docker installed on your machine. The root folder of this repo contains a [Dockerfile](/Dockerfile)
that creates an environment with Rust (needed for the [Circom](https://github.com/iden3/circom) compiler) and Node (needed for [snarkjs](https://www.npmjs.com/package/snarkjs)). 

First, build a docker image called `circom-playground`:
```
git clone https://github.com/TtheBC01/circom-playground.git
cd circom-playground
docker build -t circom-playground .
```

or pull the pre-built docker image if you don't want to wait for the circom compiler to build:

```
docker pull tthebc01/circom-playground
```

Next, fire up an interactive environment with this new image:
```
docker run -it --rm --entrypoint bash -v /home/todd/code/circom-playground/:/root/circuits circom-playground
```

this will start a bash terminal in the docker environment. Then change directories into your mounted volume:

```
cd circuits
```

> **Warning**<br>
The above command uses the `-v` flag to mount the repository into the container environment so you can edit your code without stopping, rebuilding, then 
restarting your container. Be sure to change `/home/todd/code/circom-playground` to the correct path on your machine or you won't see the files you need 
in the working directory.

Now you're all set up to start using Circom and snarkjs.

## Part 2: Compile the proof-of-membership circuit

This example is actually pretty useful in practice. The circuit for proving [inclusion in a merkle tree](/examples/merkle-tree/tree.circom) is representative of the circuit complexity needed to do useful things. We'll be borrowing some circuit templates from [circomlib](https://github.com/iden3/circomlib), specifically circuits for computing the [poseidon hash](https://www.poseidon-hash.info/) and an input mixer circuit. 

In order to compile the circuit, we need the circom compiler (already built for you in the container environment)

```
cd /examples/merkle-tree
# compile the circuit into R1CS and output wasm executable needed to compute your witness later
# output some debugging symbols you can use to explore the R1CS file
circom tree.circom --r1cs --wasm --sym 
```

The compilation command produced a [`.wasm`](https://webassembly.org/) file that can run in the browser (notice how we used a `node` runtime to 
compute the witness). The `.wasm` file is your fully compiled circuit and is used, along with an variable input file, to generate a witness file for your 
specific circuit.

So, in practice the `.wasm` file will be a dependency of your client-side application. It will run on your end user's device and it will be called
every time a proof needs to be generated (which could be often). 

Inspect the R1CS file created by the compilation step:

```
snarkjs r1cs info tree.r1cs
```

Print the constraints (this will create quite a lot of output):

```
snarkjs r1cs print tree.r1cs tree.sym
```

## Part 3: Perform the trusted setup ceremony

Now that your circuit is compiled and you have it in the form of a R1CS, its time to generate the common reference string (aka, magic numbers). We are going to use snarkjs for this. The first phase is often called the [Powers of Tau](https://medium.com/coinmonks/announcing-the-perpetual-powers-of-tau-ceremony-to-benefit-all-zk-snark-projects-c3da86af8377) and is only ever done once; it has no dependency on the computational graph of your circuit. 

```
snarkjs powersoftau new bn128 12 pot12_0000.ptau -v
snarkjs powersoftau contribute pot12_0000.ptau pot12_0001.ptau --name="First contribution" -v
snarkjs powersoftau prepare phase2 pot12_0001.ptau pot12_final.ptau -v # create CRS with all participants contributions
```

The second phase of depends on your specific circuit, specifically its R1CS. The quantity of magic numbers required to construct
a zkSNARK is proportional to the size of your circuit, so if you change the computation, you need to redo phase 2 of the trusted setup. 

```
snarkjs groth16 setup multiplier2.r1cs pot12_final.ptau multiplier2_0000.zkey # create a compatible key
snarkjs zkey contribute multiplier2_0000.zkey multiplier2_0001.zkey --name="1st Contributor Name" -v # use the key to contribute your own randomness
snarkjs zkey export verificationkey multiplier2_0001.zkey verification_key.json # export your key to a json file for later
```

In practice, if your application is proving the same kind of statement over and over again with different private inputs (this will most likely be the case), then both phase I and II need only be done a single time before you officially launch your application into production. If you have a situation
where you don't know the circuits ahead of time, you'll need to run phase II once for each new circuit introduced (because we are using Groth16). 

## Part 4: Generate a Proof

Now that we have compiled our circuit and successfully completed the trusted setup ceremony, a prover has everything it needs to start generating proofs.

First, use the `.wasm` file you compiled along with an input file containing all the public and private inputs to output a special witness file. 

Then, use the publicly available proving key from the trusted setup along with the witness to output a json file containing your proof as well 
as a separate file that contains just the public information that the verifier will need. 

```
# this first step will compute a special binary-format witness file
node ./multiplier2_js/generate_witness.js ./multiplier2_js/multiplier2.wasm input.json witness.wtns # run the compiled circuit against your input
# your outputs here are proof.json and public.json
# they need to be communicated to the verifier 
snarkjs groth16 prove multiplier2_0001.zkey witness.wtns proof.json public.json
```

## Part 5: Verify the Proof

Now that the proof and public inputs have been delivered to the verifier, use the publicly available verification key to verify their contents:

```
snarkjs groth16 verify verification_key.json public.json proof.json
```

Proofs generated for zkSNARKS can also be verified on smart contract platforms like Ethereum. The Ethereum Virtual Machine introduced special routines
(EIP196 and EIP197) in an attempt to make zkSNARK proof verification as efficient (and thus cheap) as possible. This is what makes token mixers like
Tornado Cash feasible to implement and use on the Etheruem blockchain.

> **Note**<br>
Try changing something small in `proof.json` or `public.json` file so that the proof doesn't verify.