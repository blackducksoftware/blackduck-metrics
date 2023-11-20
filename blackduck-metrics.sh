#!/bin/bash

get_path_separator() {
  # Performs a check to see if the system is Windows based.
  if [[ `uname` == *"NT"* ]] || [[ `uname` == *"UWIN"* ]]; then
    echo "\\"
  else
    echo "/"
  fi
}

# To override the default version key, specify a
# different METRICS_VERSION_KEY in your environment and
# *that* key will be used to get the download url from
# artifactory. These METRICS_VERSION_KEY values are
# properties that resolve to download
# urls for the metrics jar file.
# Every version of Black Duck Metrics will have its own
# key.
METRICS_VERSION_KEY=${METRICS_VERSION_KEY:-LATEST}

# To override the default location of $HOME/blackduck-metrics, specify
# your own JAR_DOWNLOAD_DIR in your environment and
# *that* location will be used.
# *NOTE* We currently do not support spaces in the
# JAR_DOWNLOAD_DIR.
DEFAULT_JAR_DOWNLOAD_DIR="${HOME}$(get_path_separator)blackduck-metrics$(get_path_separator)download"

JAR_DOWNLOAD_DIR=${JAR_DOWNLOAD_DIR:-${DEFAULT_JAR_DOWNLOAD_DIR}}

# To control which java metrics will use to run, specify
# the path in in METRICS_JAVA_PATH or JAVA_HOME in your
# environment, or ensure that java is first on the path.
# METRICS_JAVA_PATH will take precedence over JAVA_HOME.
# JAVA_HOME will take precedence over the path.
# Note: METRICS_JAVA_PATH should point directly to the
# java executable. For JAVA_HOME the java executable is
# expected to be in JAVA_HOME/bin/java
METRICS_JAVA_PATH=${METRICS_JAVA_PATH:-}

# If you want to pass any java options to the
# invocation, specify METRICS_JAVA_OPTS in your
# environment. For example, to specify a 6 gigabyte
# heap size, you would set METRICS_JAVA_OPTS=-Xmx6G.
METRICS_JAVA_OPTS=${METRICS_JAVA_OPTS:-}

METRICS_SOURCE=

# If you want to pass any additional options to
# curl, specify METRICS_CURL_OPTS in your environment.
# For example, to specify a proxy, you would set
# METRICS_CURL_OPTS=--proxy http://myproxy:3128
METRICS_CURL_OPTS=${METRICS_CURL_OPTS:-}

# If you only want to download the appropriate jar file set
# this to 1 in your environment. This can be useful if you
# want to invoke the jar yourself but do not want to also
# get and update the jar file when a new version releases.
METRICS_DOWNLOAD_ONLY=${METRICS_DOWNLOAD_ONLY:-0}

SCRIPT_ARGS="$@"
LOGGABLE_SCRIPT_ARGS=""


# Wrapper script to validate Java is installed and available and the jar file can be found.
# Example usage : blackduck-metrics-export.sh -url https://52.213.63.19 -apikey NDAxZTViMzctNjVjNS00YjczLWJhYjAtOWU1OWMzNWZhODA1OjFhZWZlZTNhLWQxZmQtNDVlMy05MGJmLTFjNTA5ZjhjYWQ0AQ== -outputDir ./blackduck-metrics-export -trusthttps

METRICS_BINARY_REPO_URL=https://raw.githubusercontent.com/blackducksoftware/blackduck-metrics/main/

validate_java() {
  if ! command -v java &> /dev/null
  then
      echo "Java could not be found.  Either it is not installed or you need to specify the JAVA_HOME environment variable pointing to the Java folder."
      exit
  else
    echo "Java found."
  fi
}

run() {
  localjar=(blackduck-metrics-*-jar-with-dependencies.jar)

  if test -f "${localjar[0]}"; then
    JAR_DESTINATION=${localjar[0]}
    echo "Using local jar $JAR_DESTINATION"
  else
    get_metrics
  fi

  if [[ ${METRICS_DOWNLOAD_ONLY} -eq 0 ]]; then
    validate_java
    run_metrics
  fi
}

get_metrics() {
  PATH_SEPARATOR=$(get_path_separator)
  USE_LOCAL=0

  LOCAL_FILE="${JAR_DOWNLOAD_DIR}${PATH_SEPARATOR}blackduck-metrics-last-downloaded-jar.txt"
  echo "Version ${METRICS_VERSION_KEY}"
  VERSION_CURL_CMD="curl ${METRICS_CURL_OPTS} --silent --header \"X-Result-Detail: info\" '${METRICS_BINARY_REPO_URL}blackduck-metrics-properties.txt'"
  VERSION_EXTRACT_CMD="${VERSION_CURL_CMD} | grep \"${METRICS_VERSION_KEY}\" | sed 's/[^[]*[^\"]*\"\([^\"]*\).*/\1/'"
  METRICS_SOURCE=$(eval ${VERSION_EXTRACT_CMD})
  echo "Metrics Source ${METRICS_SOURCE}"
  if [[ -z "${METRICS_SOURCE}" ]]; then
    echo "Unable to derive the location of ${METRICS_VERSION_KEY} from response to: ${VERSION_CURL_CMD}"
    USE_LOCAL=1
  fi

  if [[ USE_LOCAL -eq 0 ]]; then
    echo "Will look for : ${METRICS_SOURCE}"
  else
    echo "Will look for : ${LOCAL_FILE}"
  fi

  if [[ USE_LOCAL -eq 1 ]] && [[ -f "${LOCAL_FILE}" ]]; then
    echo "Found local file ${LOCAL_FILE}"
    METRICS_FILENAME=`cat ${LOCAL_FILE}`
  elif [[ USE_LOCAL -eq 1 ]]; then
    echo "${LOCAL_FILE} is missing and unable to communicate with a Black Duck Metrics source."
    exit -1
  else
    METRICS_FILENAME=${METRICS_FILENAME:-$(awk -F "/" '{print $NF}' <<< $METRICS_SOURCE)}
  fi

  JAR_DESTINATION="${JAR_DOWNLOAD_DIR}${PATH_SEPARATOR}${METRICS_FILENAME}"

  USE_REMOTE=1
  if [[ USE_LOCAL -ne 1 ]] && [[ ! -f "${JAR_DESTINATION}" ]]; then
     echo "You don't have the current file, so it will be downloaded."
  else
     echo "You have already downloaded the latest file, so the local file will be used."
     USE_REMOTE=0
  fi

  if [ ${USE_REMOTE} -eq 1 ]; then
      echo "getting ${METRICS_SOURCE} from remote"
      TEMP_JAR_DESTINATION="${JAR_DESTINATION}-temp"
      curlReturn=$(curl ${METRICS_CURL_OPTS} --silent -w "%{http_code}" -L -o "${TEMP_JAR_DESTINATION}" --create-dirs "${METRICS_SOURCE}")
      if [[ 200 -eq ${curlReturn} ]]; then
        mv "${TEMP_JAR_DESTINATION}" "${JAR_DESTINATION}"
        if [[ -f ${LOCAL_FILE} ]]; then
          rm "${LOCAL_FILE}"
        fi
        echo "${METRICS_FILENAME}" >> "${LOCAL_FILE}"
        echo "saved ${METRICS_SOURCE} to ${JAR_DESTINATION}"
      else
        echo "The curl response was ${curlReturn}, which is not successful - please check your configuration and environment."
        exit -1
      fi
    fi
}


set_metrics_java_path() {
  PATH_SEPARATOR=$(get_path_separator)

  if [[ -n "${METRICS_JAVA_PATH}" ]]; then
    echo "Java Source: METRICS_JAVA_PATH=${METRICS_JAVA_PATH}"
  elif [[ -n "${JAVA_HOME}" ]]; then
    METRICS_JAVA_PATH="${JAVA_HOME}${PATH_SEPARATOR}bin${PATH_SEPARATOR}java"
    echo "Java Source: JAVA_HOME${PATH_SEPARATOR}bin${PATH_SEPARATOR}java=${METRICS_JAVA_PATH}"
  else
    echo "Java Source: PATH"
    METRICS_JAVA_PATH="java"
  fi
}

run_metrics() {
  set_metrics_java_path

  JAVACMD="\"${METRICS_JAVA_PATH}\" ${METRICS_JAVA_OPTS} -jar \"${JAR_DESTINATION}\""
  echo "running Black Duck Metrics: ${JAVACMD} ${LOGGABLE_SCRIPT_ARGS}"

  eval "${JAVACMD} ${SCRIPT_ARGS}"
  RESULT=$?
  echo "Result code of ${RESULT}, exiting"
  exit ${RESULT}
}

run