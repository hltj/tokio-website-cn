#!/usr/bin/env bash

if [[ "$TRAVIS_OS_NAME" == "linux" ]]
then
  git clone https://github.com/tokio-cn/tokio-cn.github.io.git ../website
  mv public ../website/
  cd ../website
  git clone https://github.com/davisp/ghp-import.git &&
  ghp-import/ghp_import.py -n -p -f -m "内容更新" -b master -r https://"$TOKIOCN_GH_TOKEN"@github.com/tokio-cn/tokio-cn.github.io.git public &&
  echo "内容已更新"
fi
