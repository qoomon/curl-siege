#!/bin/bash

trap 'echo; kill_processes $(jobs -p); exit 1' SIGINT SIGTERM

siege_time=$1
siege_delay=$2
concurrency=$3
filename=$4

request_count=0
response_success_count=0
response_fail_count=0
request_upload_time_all=0.0
request_upload_time_avg=0.0
request_time_all=0.0
request_time_avg=0.0

output_file="curl_siege$$.csv"
rm $output_file

function print_stats {
  # echo "--------------------------------"
  # echo -e "run_time:\t $(bc -l <<< "$(date +%s.000) - $start_time ")s"
  # echo -e "count:\t\t $request_count"
  # echo -e "success:\t $response_success_count"
  # echo -e "fail:\t\t $response_fail_count"
  # echo -e "time_avg:\t $(printf "%0.3f\n" $response_time_avg)s"
  # echo "--------------------------------"

  echo  "$request_count,$(printf "%0.3f\n" $request_upload_time_avg),$(printf "%0.3f\n" $request_time_avg)" >> $output_file
}

function kill_processes {
  for job in "$@"; do
      kill -15 $job &> /dev/null
  done
}

function response_code_color {
  case "$1" in
    2*)
      echo "\033[0;34m" # Blue
      ;;
    3*)
      echo "\033[0;33m" # Yellow
      ;;
    4*)
      echo "\033[1;31m" # Light Red
      ;;
    5*)
      echo "\033[0;31m" # Red
      ;;
    *)
      echo "\033[0;31m" # Red
      ;;
  esac
}


function catapult {
  catapult_index=$1

  trap 'echo; kill_processes $(jobs -p); print_stats; exit 0' SIGINT SIGTERM

  while true; do

    #echo "loop file: $filename"
    line_number=0
    while read line || [ -n "$line" ]; do

      line_number=$(( $line_number + 1 ))

      curl_stats="%{http_code} %{time_total} %{time_pretransfer}"

      #### Siege Format ####

      # params=($line)
      # url=${params[0]}
      # method=${params[1]}
      # data=${params[@]:2}
      # if [ -n "$data" ]; then
      #   result=($(curl -L -s -o /dev/null -w "$curl_stats" -X$method "$url" --data-binary "$data"))
      # else
      #   result=($(curl -L -s -o /dev/null -w "$curl_stats" -X$method "$url"))
      # fi

      curl_args=$line

      result=($(bash -c "curl $curl_args --silent --output /dev/null --write-out \"$curl_stats\""))

      response_code=${result[0]}
      request_time=${result[1]}
      request_upload_time=${result[2]}

      request_count=$(bc -l <<< "$request_count + 1")

      request_time_all=$(bc -l <<< "$request_time_all + $request_time")
      request_time_avg=$(bc -l <<< "$request_time_all / $request_count")

      request_upload_time_all=$(bc -l <<< "$request_upload_time_all + $request_upload_time")
      request_upload_time_avg=$(bc -l <<< "$request_upload_time_all / $request_count")

      if [[ "$response_code" = "2"* ]] || [[ "$response_code" = "3"* ]]; then
        response_success_count=$(bc -l <<< "$response_success_count + 1")
      else
        response_fail_count=$(bc -l <<< "$response_fail_count + 1")
      fi

      reset_color="\033[0;0m" # White
      log_color=$(response_code_color $response_code) # White

      echo -e "$log_color""catapult: $catapult_index\t line: $line_number\t code: $response_code\t time_up_avg: $(printf "%0.3f\n" $request_upload_time_avg)s\t time: $request_time\t time_avg: $(printf "%0.3f\n" $request_time_avg)s\t count: $request_count\t success: $response_success_count\t fail: $response_fail_count\t run_time:$(bc -l <<< "$(date +%s.000) - $start_time ")s$reset_color"
      sleep $(bc <<< "$RANDOM % ( $siege_delay + 1 )")

    done < $filename
  done
}

start_time=$(date +%s)
end_time=$(( $start_time + $siege_time ))

catapult_pids=""
for catapult_index in $(seq 1 $concurrency) ; do
  echo "setup catapult $catapult_index"
  catapult $catapult_index &
  catapult_pids="$catapult_pids $!"
done
# destroy catapults after siege time expires
{
  while [ $(date +%s) -lt $end_time ]; do sleep 1; done; kill_processes $catapult_pids &
} &

wait
cat $output_file