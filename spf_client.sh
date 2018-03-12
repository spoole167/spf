#!/bin/bash

run_jetty() {

  echo "run jetty"

  export JAVA=$JAVA_HOME/bin/java

  # turn on logging
  echo "--module=console-capture" >> /spf/servers/jetty/start.ini

  # redirect logging
  rm -rf /spf/servers/jetty/logs
  ln -s $spf_logs /spf/servers/jetty/logs
  rm -f $spf_logs/*

  /spf/servers/jetty/bin/jetty.sh start

  ( tail -f  $spf_logs/* & ) | grep -q "\($spf_ready_msg\|OutOfMemoryError\)"

}
run_tomcat() {

  echo "run tomcat"
  echo "completion msg:$spf_ready_msg"

  logfile="$spf_logs/catalina.out"
  rm -f $logfile
  export CATALINA_OUT=$logfile
  /spf/servers/tomcat/bin/catalina.sh start

  ( tail -f  $logfile & ) | grep -q "\($spf_ready_msg\|OutOfMemoryError\)"

  r= $(cat $logfile | grep -q "\($spf_ready_msg\|OutOfMemoryError\)")
  echo "[$r]"
  echo "tomcat run complete "

}


run_standalone() {

  echo "run standalone"

  java_launcher=$JAVA_HOME/bin/java
  logfile="$spf_logs/log.txt"
  rm -f $logfile
  cmd="$java_launcher $javaopts -jar /spf/app/app.war "

  echo "running $cmd"

  $cmd &> $logfile &

  ( tail -f  $logfile & ) | grep -q "\($spf_ready_msg\|OutOfMemoryError\)"

  echo "done running test"

}

config_openj9() {


  case $spf_mode in

    "container")
      spf_jvmopts+=" -Xquickstart -XX:+IdleTuningGcOnIdle -Xtune:virtualized"

    ;;
    "standard")
      # do nothing - ie set no special configs
    ;;
    "shared")

      spf_jvmopts+=" -Xquickstart  -XX:+IdleTuningGcOnIdle -Xtune:virtualized -Xscmaxaot100m -Xscmx1G -Xshareclasses:cacheDir=${spf_cache},persistent "

    ;;
  esac
}

config_hotspot() {


  case $spf_mode in

    "container") ;;
    "standard") ;;
    "shared")

      spf_jvmopts+="  -Xshare:on -XX:+UnlockDiagnosticVMOptions -XX:SharedArchiveFile=${spf_cache}/cache.jsa"
    ;;
  esac


}


#
# function to gather docker memory stats
#
gather_stats() {
  container_id=$(cat /proc/self/cgroup | head -n 1   | sed "s/.*docker\/\(.*\)/\1/")
  curl -L -s --unix-socket /var/run/docker.sock "http://docker/containers/$container_id/stats" > /tmp/data &
  stats_tool=$!
}


while getopts ":c" opt; do
  case $opt in

    c)
      bash
      exit 1
    ;;


    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
    ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
    ;;
  esac

done


# load config
. /spf/tmp/config


# check we have a app is ready msg
varname="spf_ready_msg_$spf_appserver"
spf_ready_msg=${!varname}

if [ "$spf_ready_msg" == "" ] ; then
  echo "SPFError: missing ready message. Needs variable called $varname in config"
  exit 1
fi

#
#  echo "spf_test_run=$spf_test_run"
#  echo "spf_appserver=$spf_appserver"
#  echo "spf_java_version=$spf_java_version"
#  echo "spf_jvm=$spf_jvm"
#  echo "spf_heap_size=$spf_heap_size"
#  echo "spf_mode=$spf_mode"


# setup java config  (defults here)

spf_jvmopts="-Xmx${spf_heap_size}m "

run_tmp="/spf/tmp/cache/$spf_jvm/$spf_java_version/$spf_heap_size/$spf_mode/$spf_appserver/"
mkdir -p $run_tmp

# JVM cache dir
spf_cache="$run_tmp/cache"
mkdir -p $spf_cache

# logs dir
spf_logs="$run_tmp/logs"
mkdir -p $spf_logs

#
# Clean old cache data if run is #1
#
if [  "$spf_test_run" == "1" ]
then
  rm -rf ${spf_logs}/*
  rm -rf ${spf_cache}/*
fi

spf_results_dir="/spf/results/$spf_jvm/$spf_java_version/$spf_heap_size/$spf_mode/$spf_appserver/"
mkdir -p $spf_results_dir


export JAVA_HOME="/spf/runtimes/java/$spf_java_version/$spf_jvm"

# jvm specific configs...


case $spf_jvm in

  "openj9"  ) config_openj9 ;;
  "hotspot" )config_hotspot ;;

  *) echo "java runtime not recognised [$spf_jvm]"
    exit 1
  ;;
esac

export JAVA_OPTIONS="$spf_jvmopts"
export JAVA_OPTS="$spf_jvmopts"
export JVM_ARGS="$jspf_vmopts"

echo "args=$spf_jvmopts"




gather_stats


# start the timer

timestamp_start=$(date +%s%N)

  # for hotspot shared do a rebuild of the classes if pass is 1

  if [ "$spf_jvm" ==  "hotspot" ] && [ "$spf_mode" == "shared" ] && [  "$spf_test_run" == "1" ]
  then
    ${JAVA_HOME}/bin/java -Xshare:dump  -XX:+UnlockDiagnosticVMOptions  -XX:SharedArchiveFile=${spf_cache}/cache.jsa
  fi



# run server

case $spf_appserver in

  "tomcat"     ) run_tomcat ;;
  "jetty"      ) run_jetty ;;
  "standalone" ) run_standalone ;;

  *) echo "app server not recognised [$spf_appserver]"
    exit 1
  ;;
esac

timestamp_end=$(date +%s%N)

let elapsed=$timestamp_end-$timestamp_start
spf_elapsed_secs=$( echo "scale=3 ; $elapsed / 1000000000" | bc )

# dont want any horrible process terminated messages

# when we kill the stats collector
disown -r
#  wait 2 secs for last details from docker to be captured
sleep 2
# kill the collector
kill $stats_tool


# the stats file tends to have an incomplete json data last entry so it is removed before processing
# then we pull out the max usage field, do a descending numberic sort and take the 1st entry
spf_max_usage=$( cat /tmp/data  | head -n -1 | jq .memory_stats.max_usage | sort -g -r | head -n 1 )
spf_max_usage=$( echo "scale=3 ; $spf_max_usage / 1000000" | bc )

# copy the stats data out for keeping
spf_stats_dir="$spf_results_dir/stats"
mkdir -p $spf_stats_dir

spf_stats_file="$spf_stats_dir/data.json"

echo '{ "entries":[' > $spf_stats_file

cat /tmp/data  | head -n -1  >> "$spf_stats_file"
echo ']}' >> $spf_stats_file

# and do the same again with the data formated for just memory usage and cpu usage
spf_mem_usage=( $(cat /tmp/data  | head -n -1 |  jq .memory_stats.usage) )
spf_cpu_usage=( $(cat /tmp/data  | head -n -1 |  jq .cpu_stats.cpu_usage.total_usage) )

spf_extra_file="$spf_stats_dir/profile.csv"
echo "mem,cpu" > $spf_extra_file

for ((i=0;i<${#spf_mem_usage[@]};++i)); do
  echo "${spf_mem_usage[i]},${spf_cpu_usage[i]}" >> $spf_extra_file
done

#
# finally , echo out the results for capturing by the front end
#

echo "SPF::$spf_test_run,$spf_appserver,$spf_java_version,$spf_jvm,$spf_heap_size,$spf_mode,$spf_elapsed_secs,$spf_max_usage"
