firstrun=true
if $firstrun; then
touch out/fpga_impl/status.txt
touch out/fpga_impl/FreqArea.txt
fi
firstrun=false
echo "true" > out/fpga_impl/status.txt
echo "Freq/Area" > out/fpga_impl/FreqArea.txt
clk=30
zero=1
step=5
while [ $zero -eq 1 ]
do
freq=$(( 1000/clk ))
echo $freq >> out/fpga_impl/FreqArea.txt
echo "create_clock -period" $clk "[get_ports {clk}]" > warpv_constraints.xdc
make impl
past_clk=$clk
clk=`expr $clk - $step`
if [ $clk -le $step ]
then
zero=0
fi
if grep -q false out/fpga_impl/status.txt; then
    zero=0
fi
done
echo"Max clock is" $past_clk
sed -i '$ d' FreqArea.txt
sed -i '$ d' FreqArea.txt



