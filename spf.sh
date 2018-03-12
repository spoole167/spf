#!/bin/bash
#
# Executes test runs as determiend by provided config file
# or uses the default file.
#
# Tests are run in a docker container.
# Options include running stand-alone jar files
# or a WAR file in one of the supplied application servers
#
# Results are nominally output as CSV files and a series of graphs.
#
# Inputs to this script
#
#   -f config file   [ -a overide-full-path-to-application-to-test(jar or war) ]
#
#

# builds a config file for the test

# docker runner
# calls docker with all the info needed..

run_test() {

  # input params are:  run_number server java_version java_runtime heap_size test_mode

  echo "run $1 $2 $6 mode using $4 v $3  -Xmx:$5m"

  #
  # build docker command
  #
  docker_command="docker run -P -it -v /var/run/docker.sock:/var/run/docker.sock "
  docker_command+="-v ${spf_output_dir}:/spf/results "
  docker_command+="-v ${spf_tmp_dir}:/spf/tmp "


  # add any overide for application dir
  #
  if [ -n "${local_app}" ]; then
    docker_command+="-v ${local_app}:/spf/app/app.war"
  fi


  # copy in config info

  config_file=${spf_tmp_dir}/config
  cp .default.config $config_file

  # add and local configs..

  if [ "$conf" != "" ] ; then
    echo "#local conf "   >> $config_file
    cat $conf >> $config_file
  fi

  docker_command+=" spf "

  # add run specific info
  echo "#test run"             >> ${config_file}
  echo "spf_test_run=$1"       >> ${config_file}
  echo "spf_appserver=$2"      >> ${config_file}
  echo "spf_java_version=$3"   >> ${config_file}
  echo "spf_jvm=$4"            >> ${config_file}
  echo "spf_heap_size=$5"      >> ${config_file}
  echo "spf_mode=$6"           >> ${config_file}


  if [ "$console" == true ]; then
      docker_command+=" -c"
  fi
  # run
  echo $docker_command
  $docker_command

}

calc_total_tests() {
  spf_test_count=0
  for n in $(seq 1 $spf_test_runs) ; do
    for s in  "${spf_appservers[@]}" ; do
      for v in  "${spf_java_versions[@]}"  ; do
        for j in  "${spf_jvms[@]}"  ; do
          for h in  "${spf_heap_sizes[@]}"  ; do
            for m in  "${spf_modes[@]}"  ; do
              let spf_test_count=spf_test_count+1
            done
          done
        done
      done
    done
  done
}

#
# Main entry point
#
# load default config
. .default.config


local_app=""


# pare options

while getopts ":cf:a:" opt; do
  case $opt in

    f) conf="$OPTARG" ;;
    a) local_app="$OPTARG" ;;
    c) console=true ;;

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
# abort if not present or not a file

if [ "${conf}" != "" ]; then
  if test -f "${conf}" ; then
    . ${conf}
  else
    echo "Configuration file ${conf} is not a file or cannot be found" >&2
    exit 1
  fi
else
  echo "Configuration file not specified.  use -f option " >&2
  exit 1
fi


# overide app if provied and valid

if [ "${local_app}" != "" ]; then
  if test -f ${local_app} ; then
    spf_application=${local_app}
  else
    echo "cannot  find application file ${local_app}"
    exit 1
  fi
fi

# create local directory for output mount
mkdir -p "${spf_output_dir}"

# and clear any outstanding temporary stuff (calculated results are kept )
mkdir -p "${spf_tmp_dir}"
rm -rf  "${spf_tmp_dir}/*"


spf_jvms=(${spf_jvms//,/ })
spf_java_versions=(${spf_java_versions//,/ })
spf_appservers=(${spf_appservers//,/ })
spf_test_types=(${spf_test_types//,/ })
spf_heap_sizes=(${spf_heap_sizes//,/ })
spf_modes=(${spf_modes//,/ })


# did we load something that specified the number of runs to do?
# quick check to make sure we did load some sort of config

if [ "${spf_test_runs}" -gt 0 ] ; then
  calc_total_tests
else
 echo "Configuration invalid.  Check is valid format and has spf_test_runs set "
 exit 1
fi



spf_framework_log="${spf_output_dir}/framework.log"
echo "Stated " > "${spf_framework_log}"

echo "running spf        "
echo "app directory      : ${spf_application}"
echo "runtime(s)         : ${spf_jvms[@]}"
echo "runtime version(s) : ${spf_java_versions[@]}"
echo "app servers        : ${spf_appservers[@]}"
echo "heap size(s)       : ${spf_heap_sizes[@]}"
echo "run modes          : ${spf_modes[@]}"
echo "total tests        : ${spf_test_count}"


# now loop through all the variations of config
c=0
for n in $(seq 1 $spf_test_runs) ; do
  for s in  "${spf_appservers[@]}" ; do
    for v in  "${spf_java_versions[@]}"  ; do
      for j in  "${spf_jvms[@]}"  ; do
        for h in  "${spf_heap_sizes[@]}"  ; do
          for m in  "${spf_modes[@]}"  ; do
            let c=c+1
            echo "Runing test $c / $spf_test_count"
            if [ "$console" == true ] ; then
                run_test  $n $s $v $j $h $m
                exit 1
            else
            run_test  $n $s $v $j $h $m >> $spf_framework_log
            fi
          done
        done
      done
    done
  done
done

# pull out the Results
results_csv="${spf_output_dir}/results.csv"
echo "run,server,version,runtime,maxmem,mode,elapsed,memused" > $results_csv
cat $spf_framework_log | grep 'SPF::' | sed 's/SPF::\(.*\)/\1/' >> $results_csv
