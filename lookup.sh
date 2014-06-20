#!/bin/bash

usage() {
  cat <<-ENDOFUSAGE
Usage: $(basename $0) [OPTION] [SEARCH QUERY]

  -g [result]   Opens the specified search result
  -n            Displays the next page of the last search
  -v            Displays the previous page of the last search
  -p [page]     Displays the given page number of the last (or current) search
  -s [scope]    Specifies search scope (default "web")
                  Options: "web", "wiki", "news"
                  More can be specified in lookuprc
  -r            Repeats previous search
                  Note: Redundant; can just run $(basename $0) with no arguments
  -l [results]  Number of results to show per page (default 5)
  -h            Displays this help message

Example:
  > $(basename $0) -p 2 -s wiki -l 3 Galois Theory

      n results
    1. Result #1
    2. Result #2
    3. Result #3
  
  > $(basename $0) -n

      n results
    4. Result #4
    5. Result #5
    6. Result #6

  > $(basename $0) -g 5

    (Result #5 opened)

Notes:
  - If no search query is given, the last search (query, page numer) is assumed.
  - Browser is specified with BROWSER environment variable.

lookuprc:
  Can be configured in ~/.lookup/lookuprc
  You're on your own.

ENDOFUSAGE
  exit

}

CONFIGDIR="$HOME/.lookup"
CONFIGFILE="$CONFIGDIR/lookuprc"
LOOKUP_BROWSER="${BROWSER:-'/usr/bin/lynx'}"
HISTFILE="$CONFIGDIR/history"
LASTFILE="$CONFIGDIR/last"
GOOGLE_API_BASE="https://www.googleapis.com/customsearch/v1"
API_FIELDS="searchInformation(totalResults),items(title,snippet,displayLink,link)"
LOOKUP_WEB_CX="008385802859680878879:gfxp9yb-ftc"
LOOKUP_WIKI_CX="008385802859680878879:ll_kgxmu77i"
LOOKUP_NEWS_CX="008385802859680878879:euodv4frpji"

# initialize options
LOOKUP_NUM_RESULTS=5
LOOKUP_DEFAULT_CX="web"
LOOKUP_QUERY_COLOR=32
LOOKUP_INFO_COLOR=31
LOOKUP_LINK_COLOR=34
LOOKUP_TITLE_COLOR=34
LOOKUP_SITE_COLOR=33

if [[ -f "$CONFIGFILE" ]]; then
  . "$CONFIGFILE"
fi

if [[ ! -d "$CONFIGDIR" ]]; then
  mkdir "$CONFIGDIR"
fi

get_val() {
  echo "$PARSED" | grep "$1" | sed -r "s/^.*\t\"(.*)\"$/\1/"
}

set_scope() {
  scope="${1:-"$LOOKUP_DEFAULT_CX"}"
  upscope="$(echo "$scope" | tr '[:lower:]' '[:upper:]')"
  cx_var="LOOKUP_$upscope""_CX"
  LOOKUP_CX="${!cx_var}"

  if [[ -z "$LOOKUP_CX" ]]; then
    echo "Invalid context; using '$LOOKUP_DEFAULT_CX'"
    set_scope
  fi
}

perform_search() {
    query="$1"
    cx_name="${2:-"$LOOKUP_DEFAULT_CX"}"
    set_scope "$cx_name"
    cx="$LOOKUP_CX"
    start="${3:-"1"}"
    num="${4:-"$LOOKUP_NUM_RESULTS"}"
    next="$(( start + num ))"

    page_num="$(( (start - 1) / num + 1 ))"

    DATA="$(curl -s -G "$GOOGLE_API_BASE" \
      -d key="$LOOKUP_API_KEY" \
      -d cx="$cx" \
      -d fields="$API_FIELDS" \
      -d num="$LOOKUP_NUM_RESULTS" \
      -d alt="json" \
      -d start="$start" \
      --data-urlencode q="$query")"

    # TODO: move to awk
    PARSED=$( echo "$DATA" | JSON.sh | grep -v "\]\s[{\[]" )

    cat /dev/null > "$HISTFILE"

    cat /dev/null > "$LASTFILE"
    echo $query >> "$LASTFILE"
    echo "$cx_name" >> "$LASTFILE"
    echo "$start" >> "$LASTFILE"
    echo "$next" >> "$LASTFILE"
    echo "$num" >> "$LASTFILE"

    if [[ -n "$(echo "$PARSED" | grep "^\[\"error\"")" ]]; then
      echo -e "\tError!"
      # echo "\t> $(get_val "^\[\"error\",\"errors\",0,\"message\"\]")"
      get_val "^\[\"error\",\"errors\",[0-9]*,\"message\"\]" | while read line; do
        echo -e "\t  > \e[0;31m$line\e[00m"
      done
      echo -e "\twith search query '\e[1;$LOOKUP_TITLE_COLOR""m$query\e[00m', page $page_num, scope '$cx_name'"
      exit 0;
    fi

    echo ""
    # echo -e "\tSearch query: \e[1;$LOOKUP_QUERY_COLOR""m$query\e[00m\t\t(Page $page_num)"
    echo -e "\t\e[1;$LOOKUP_INFO_COLOR""m-- $(get_val "^\[\"searchInformation\",\"totalResults\"\]") results --\e[00m"
    echo ""

    for i in $(seq 0 $(($LOOKUP_NUM_RESULTS-1))); do
      title="$(get_val "^\[\"items\",$i,\"title\"\]" | sed -r "s/\\\\//g")"
      echo -e "    $((i+start)))\t\e[1;$LOOKUP_TITLE_COLOR""m$title\e[00m"
      weblink="$(get_val "^\[\"items\",$i,\"link\"\]")"
      echo -e "\t\e[0;$LOOKUP_LINK_COLOR""m$weblink\e[00m"

      snippet="$(get_val "^\[\"items\",$i,\"snippet\"\]" | sed -r "s/   / /g")"
      echo "> $snippet" | fold -sw 80 | while read line
      do
        echo -e "\t$line"
      done
      echo -e "\t\e[0;$LOOKUP_SITE_COLOR""m[ $(get_val "^\[\"items\",$i,\"displayLink\"\]") ]\e[00m"
      echo ""

      echo -e "[$(( i + 1 ))]\t\"$weblink\"" >> "$HISTFILE"
    done

    echo -e "\tNext page: $(basename $0) -n\t\tPrevious page: $(basename $0) -v"
    echo -e "\tGo: $(basename $0) -g #"
    echo ""
}

parse_last() {
  i=0
  IFS=$'\n'
  for line in $(cat "$LASTFILE"); do
    lastdata[$i]="$line"
    i=$(( $i + 1 ))
  done

  last_query="${lastdata[0]}"
  last_cx_name="${lastdata[1]}"
  last_start="${lastdata[2]}"
  last_next="${lastdata[3]}"
  last_num="${lastdata[4]}"
}

get_result() {
  PARSED="$(cat $HISTFILE)"
  RESULT="$(get_val "^\[$1\]")"
}

PAGE_NUM=1
LOOKUP_CX="$LOOKUP_WEB_CX"

parse_last

while getopts ":hg:p:nvs:rl:" Option
do
  case $Option in
    h)
      # help
      usage
      exit 1
      ;;
    g)
      # go
      get_result "$OPTARG"
      $BROWSER $RESULT
      exit 1
      ;;
    p)
      # page number
      PAGE_NUM="$OPTARG"
      ;;
    n)
      # next
      SEARCH_START="$last_next"
      REPEAT_QUERY=1
      ;;
    v)
      # previous
      SEARCH_START=$(( last_start - last_num ))
      if [[ "$SEARCH_START" -lt "1" ]]; then
        SEARCH_START=1
      fi
      REPEAT_QUERY=1
      ;;
    l)
      # limit
      NEW_LOOKUP_NUM_RESULTS="$OPTARG"
      ;;
    s)
      # scope
      SCOPE="$OPTARG"
      # set_scope "$OPTARG"
      ;;
    r)
      # repeat
      REPEAT_QUERY=1
      REPEAT_OPTS=1
      ;;
  esac
done
shift $(($OPTIND - 1))

LOOKUP_NUM_RESULTS="${NEW_LOOKUP_NUM_RESULTS:-"$LOOKUP_NUM_RESULTS"}"

page_start=$(( LOOKUP_NUM_RESULTS * ( PAGE_NUM - 1 ) + 1 ))
SEARCH_START=${SEARCH_START:-$page_start}

pre_query="$*"

if [[ -n "$REPEAT_QUERY" || -z "$pre_query" ]]; then
  query="${last_query}"
  LOOKUP_CX_NAME="${SCOPE:-"$LOOKUP_DEFAULT_CX"}"
  SEARCH_START="${SEARCH_START:-"$last_start"}"
  LOOKUP_NUM_RESULTS="${NEW_LOOKUP_NUM_RESULTS:-"$last_num"}"
else
  query="$*"
fi

if [[ -n "$REPEAT_OPTS" ]]; then
  LOOKUP_CX_NAME="$last_cx_name"
  SEARCH_START="$last_start"
  LOOKUP_NUM_RESULTS="$last_num"
fi

perform_search "$query" "$LOOKUP_CX_NAME" "$SEARCH_START" "$LOOKUP_NUM_RESULTS"

# TODO
# - move parser to awk
# - render bolding in description
