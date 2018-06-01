#!/usr/bin/env bash

set -x

tmp=/tmp/cephtest-mon-caps-madness

exit_on_error=1

[[ ! -z $TEST_EXIT_ON_ERROR ]] && exit_on_error=$TEST_EXIT_ON_ERROR

if [ `uname` = FreeBSD ]; then
    ETIMEDOUT=60
else
    ETIMEDOUT=110
fi

# monitor drops the subscribe message from client if it does not have enough caps
# for read from mon. in that case, the client will be waiting for mgrmap in vain,
# if it is instructed to send a command to mgr. "pg dump" is served by mgr. so,
# we need to set a timeout for testing this scenario.
export CEPH_ARGS='--rados-mon-op-timeout=5'

expect()
{
  cmd=$1
  expected_ret=$2

  echo $cmd
  eval $cmd >&/dev/null
  ret=$?

  if [[ $ret -ne $expected_ret ]]; then
    echo "Error: Expected return $expected_ret, got $ret"
    [[ $exit_on_error -eq 1 ]] && exit 1
    return 1
  fi

  return 0
}

expect "ceph auth get-or-create client.bazar > $tmp.bazar.keyring" 0
expect "ceph -k $tmp.bazar.keyring --user bazar mon_status" 13
ceph auth del client.bazar

c="'allow command \"auth ls\", allow command mon_status'"
expect "ceph auth get-or-create client.foo mon $c > $tmp.foo.keyring" 0
expect "ceph -k $tmp.foo.keyring --user foo mon_status" 0
expect "ceph -k $tmp.foo.keyring --user foo auth ls" 0
expect "ceph -k $tmp.foo.keyring --user foo auth export" 13
expect "ceph -k $tmp.foo.keyring --user foo auth del client.bazar" 13
expect "ceph -k $tmp.foo.keyring --user foo osd dump" 13
expect "ceph -k $tmp.foo.keyring --user foo pg dump" $ETIMEDOUT
expect "ceph -k $tmp.foo.keyring --user foo quorum_status" 13
ceph auth del client.foo

c="'allow command service with prefix=list, allow command mon_status'"
expect "ceph auth get-or-create client.bar mon $c > $tmp.bar.keyring" 0
expect "ceph -k $tmp.bar.keyring --user bar mon_status" 0
expect "ceph -k $tmp.bar.keyring --user bar auth ls" 13
expect "ceph -k $tmp.bar.keyring --user bar auth export" 13
expect "ceph -k $tmp.bar.keyring --user bar auth del client.foo" 13
expect "ceph -k $tmp.bar.keyring --user bar osd dump" 13
expect "ceph -k $tmp.bar.keyring --user bar pg dump" $ETIMEDOUT
expect "ceph -k $tmp.bar.keyring --user bar quorum_status" 13
ceph auth del client.bar

rm $tmp.bazar.keyring $tmp.foo.keyring $tmp.bar.keyring

echo OK
