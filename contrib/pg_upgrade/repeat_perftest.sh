#!/usr/bin/env bash


double_size()
{
    echo "doubling size..."
    echo `date`
    gpstart -a
    psql -d postgres -c "insert into erase select * from erase;"
    psql -d postgres -c "checkpoint;"
    psql -d postgres -c "vacuum;"
    psql -d postgres -c "select gp_segment_id, count(gp_segment_id) from erase group by gp_segment_id;"
    gpstop -a
}

for i in 1 2
do
    for j in 1 2
    do
	echo "running perfcheck..."
	make perfcheck  > "20181106_$i_$j.log" 2>&1
    done
    double_size
done
