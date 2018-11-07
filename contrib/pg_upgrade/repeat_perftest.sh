#!/usr/bin/env bash


double_size()
{
	echo "doubling size..."
	echo `date`
	gpstart -a
	psql -d postgres -c "insert into foo select * from foo;"
	psql -d postgres -c "checkpoint;"
	psql -d postgres -c "vacuum;"
	psql -d postgres -c "select gp_segment_id, count(gp_segment_id) from foo group by gp_segment_id;"
	gpstop -a
}

for i in 2 4 8 16
do
	for j in 1 2 3 
	do
		echo "running perfcheck..."
		make perfcheck  > "20181106_$i$j.log" 2>&1
	done
	double_size
done

