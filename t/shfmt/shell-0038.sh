cat | if (while read l; do check $l || exit 1; done)
then
	echo OK
else
	while read rest; do
		echo $rest
	done
fi
