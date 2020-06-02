#initializing files at first run

outDir=out/
statusFile=out/status.txt
FreqArea=out/FreqArea.txt

if [[ -d "$outDir" ]]
then
echo "$outDir exists on your filesystem."
else
mkdir $outDir
fi

touch $statusFile
touch $FreqArea
echo "true" > $statusFile
echo "Freq/Area" > $FreqArea



#intitializing clk/ step
clk=5
stopflag=0
step=1
num=1

#finding best freq
while [ $stopflag -eq 0 ]
do
freq=$(( 1000/clk ))
echo "Run num $num" >>$FreqArea
echo "Freq = $freq" >> $FreqArea
echo "create_clock -period" $clk "[get_ports {clk}]" > warpv_constraints.xdc
pushd ../ ; make impl; popd

#updating clk
succ_clock=$past_clk
past_clk=$clk
clk=`expr $clk - $step`
num=`expr $num + 1`

#step check
if [ $past_clk -le $step ]
then
stopflag=1
succ_clock=$past_clk
fi

#timing check
if grep -q false $statusFile; then
stopflag=1
fi

done
sed -i '$ d' $FreqArea
sed -i '$ d' $FreqArea
sed -i '$ d' $FreqArea
rm ../vi*
rm ../tight_setup_hold_pins.txt
echo "Max clock is" $succ_clock




