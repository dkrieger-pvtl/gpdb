from hamcrest import *
import os.path
import shutil
import tempfile
import unittest
import json

import release
from release import Environment

# GETVERSION_TEMPLATE = """\
# #!/bin/bash
# GP_VERSION=%(version)s

# %(tail)s
# """


class EnvironmentTest(unittest.TestCase):
  class MockCommandRunner(object):
    def __init__(self, cwd='/proper/git/directory'):
      self.cwd = cwd
      self.subprocess_mock_outputs = {}
      self.respond_to_command_with(
          ('git', '--version'), output='git version 2.10.2')
      self.respond_to_command_with(
          ('git', 'status', '--porcelain'), output='')
      self.respond_to_command_with(
          ('git', 'rev-parse', '--show-toplevel'), output='/proper/git/directory')
      self.respond_to_command_with(
          ('git', 'ls-remote', 'origin', 'master'), output='abc123def456a78912323434\trefs/heads/master')
      self.respond_to_command_with(
          ('git', 'rev-parse', 'HEAD'), output='abc123def456a78912323434')
      self.respond_to_command_with(
          ('git', 'ls-remote', 'origin', '2>/dev/null'), exit_code=0)

    def respond_to_command_with(self, cmd, output=None, exit_code=0):
      self.subprocess_mock_outputs[cmd] = (output, exit_code)

    def get_subprocess_output(self, cmd):
      return self.subprocess_mock_outputs[cmd][0]

    def subprocess_is_successful(self, cmd):
      return 0 == self.subprocess_mock_outputs[cmd][1]

  def test_check_dependencies(self):
    environment = Environment(command_runner=self.MockCommandRunner())
    result = environment.check_dependencies()
    assert_that(result)

  def test_check_dependencies_when_git_too_old(self):
    command_runner = self.MockCommandRunner()
    command_runner.respond_to_command_with(
        ('git', '--version'), output='git version 1.7.0')

    environment = Environment(command_runner=command_runner)
    result = environment.check_dependencies()
    assert_that(result, equal_to(False))

  def test_check_git_can_pull(self):
    environment = Environment(command_runner=self.MockCommandRunner())
    result = environment.check_git_can_pull()
    assert_that(result)

  def test_check_git_can_pull_fails(self):
    command_runner = self.MockCommandRunner()
    command_runner.respond_to_command_with(
        ('git', 'ls-remote', 'origin', '2>/dev/null'), exit_code=128)

    environment = Environment(command_runner=command_runner)
    result = environment.check_git_can_pull()
    assert_that(result, equal_to(False))

  def test_check_git_status(self):
    environment = Environment(command_runner=self.MockCommandRunner())
    result = environment.check_git_status()
    assert_that(result)

  def test_check_git_status_cwd_can_be_relative_path(self):
    current_working_directory = os.getcwd() # we're relying on the real OS for this test. Maybe better to inject something?
    cwd_sibling_relative_path = '../sibling_dir'
    cwd_sibling_absolute_path = os.path.abspath(os.path.join(current_working_directory, cwd_sibling_relative_path))
    command_runner = self.MockCommandRunner(cwd=cwd_sibling_relative_path)
    command_runner.respond_to_command_with(
        ('git', 'rev-parse', '--show-toplevel'), output=cwd_sibling_absolute_path)

    environment = Environment(command_runner=command_runner)
    result = environment.check_git_status()
    assert_that(result)

  def test_check_git_status_not_a_git_repo(self):
    command_runner = self.MockCommandRunner(cwd='/not/a/git/dir')
    command_runner.respond_to_command_with(
        ('git', 'rev-parse', '--show-toplevel'), output=None)

    environment = Environment(command_runner=command_runner)
    result = environment.check_git_status()
    assert_that(result, equal_to(False))

  def test_check_git_status_not_at_root_of_git_repo(self):
    command_runner = self.MockCommandRunner(cwd='/proper/git/directory/too/far/down')
    command_runner.respond_to_command_with(
        ('git', 'rev-parse', '--show-toplevel'), output='/proper/git/directory')

    environment = Environment(command_runner=command_runner)
    result = environment.check_git_status()
    assert_that(result, equal_to(False))

  def test_check_git_status_dirty(self):
    command_runner = self.MockCommandRunner()
    command_runner.respond_to_command_with(
        ('git', 'status', '--porcelain'), output='M commit_me.py')

    environment = Environment(command_runner=command_runner)
    result = environment.check_git_status()
    assert_that(result, equal_to(False))

  def test_check_git_head_is_latest(self):
    command_runner = self.MockCommandRunner()

    environment = Environment(command_runner=command_runner)
    result = environment.check_git_head_is_latest()
    assert_that(result)

  def test_check_git_head_is_not_latest(self):
    command_runner = self.MockCommandRunner()
    command_runner.respond_to_command_with(
        ('git', 'ls-remote', 'origin', 'master'), output='add123456\trefs/heads/master')
    command_runner.respond_to_command_with(
        ('git', 'rev-parse', 'HEAD'), output='bad987764')

    environment = Environment(command_runner=command_runner)
    result = environment.check_git_head_is_latest()
    assert_that(result, equal_to(False))

  def test_check_git_remote_not_authorized(self):
    command_runner = self.MockCommandRunner()
    command_runner.respond_to_command_with(
        ('git', 'ls-remote', 'origin', 'master'), output=None)
    command_runner.respond_to_command_with(
        ('git', 'rev-parse', 'HEAD'), output='bad987764')

    environment = Environment(command_runner=command_runner)
    result = environment.check_git_head_is_latest()
    assert_that(result, equal_to(False))

  def test_check_has_file(self):
    existing_files = set([
        '/proper/git/directory/file/in_repo',
        '/proper/git/directory/another_file',
        '/outside/outside_file',
    ])
    def exists(path):
      return path in existing_files
    environment = Environment(command_runner=self.MockCommandRunner())
    assert_that(environment.check_has_file('file/in_repo', os_path_exists=exists), equal_to(True))
    assert_that(environment.check_has_file('another_file', os_path_exists=exists), equal_to(True))
    assert_that(environment.check_has_file('file_not_in_repo', os_path_exists=exists), equal_to(False))
    assert_that(environment.check_has_file('outside_file', os_path_exists=exists), equal_to(False))


# class AwsTest(unittest.TestCase):
#   class MockBucketExists(object):
#     def load():
#       pass

#   class MockBucketDoesntExist(object):
#     def load():
#       # throw the botocore 404 exception
#       pass

#   def TestBucketExistsItDoes(self):
#     bucket = MockBucket()
#     aws = Aws(


class ReleaseTest(unittest.TestCase):
  class MockCommandRunner(object):
    def __init__(self, cwd='/proper/git/directory'):
      self.cwd = cwd
      self.subprocess_mock_outputs = {}
      self.respond_to_command_with(
          ('git', 'rev-parse', '--verify', '--quiet', 'HEAD'), exit_code=0)

    def respond_to_command_with(self, cmd, output=None, exit_code=0):
      self.subprocess_mock_outputs[cmd] = (output, exit_code)

    def get_subprocess_output(self, cmd):
      return self.subprocess_mock_outputs[cmd][0]

    def subprocess_is_successful(self, cmd):
      return 0 == self.subprocess_mock_outputs[cmd][1]

  class MockBucket(object):
    class MockPolicy(object):

      def __init__(self):
        self.policy_json = None

      def put(self, Policy=None):
        self.policy_json = Policy

    class MockVersioning(object):

      def __init__(self):
        self.status = None

      def enable(self):
        self.status = 'Enabled'

    def __init__(self, name, exists_in_s3 = False):
      self.name = name
      self.was_created = False
      self.exists_in_s3 = exists_in_s3
      self.bucket_policy = self.MockPolicy()
      self.bucket_versioning = self.MockVersioning()

    def create(self, **kwargs):
      self.region = kwargs.get('CreateBucketConfiguration', {}).get('LocationConstraint')
      if self.exists_in_s3:
        raise StandardError('MockBucket: already exists: ' + self.name)
      self.was_created = True

    def Policy(self):
      return self.bucket_policy

    def Versioning(self):
      return self.bucket_versioning

  class MockAWS(object):
    def __init__(self, *buckets):
      self.buckets = buckets

    def get_botobucket(self, bucket_name):
      return next((b for b in self.buckets if b.name == bucket_name), None)

    def bucket_exists(self, bucket):
      return bucket.exists_in_s3

  def test_check_rev(self):
    release_with_good_rev = release.Release('1.2.3', 'HEAD', command_runner=self.MockCommandRunner())
    assert_that(release_with_good_rev.check_rev())

  def test_check_bad_rev(self):
    command_runner = self.MockCommandRunner()
    command_runner.respond_to_command_with(
          ('git', 'rev-parse', '--verify', '--quiet', 'DEADBEEF'), exit_code=1)

    release_with_bad_rev = release.Release('1.2.3', 'DEADBEEF', command_runner=command_runner)
    assert_that(release_with_bad_rev.check_rev(), equal_to(False))

  def test_create_release_bucket(self):
    bucket = self.MockBucket('gpdb-4.3.10.0-concourse')
    aws = self.MockAWS(bucket)
    release_with_good_aws = release.Release('4.3.10.0', '123abc', aws=aws)

    release_with_good_aws.create_release_bucket()
    assert_that(bucket.was_created, equal_to(True))
    assert_that(bucket.region, equal_to('us-west-2'))

  def test_create_release_bucket_when_exists_in_s3_does_not_call_create(self):
    bucket = self.MockBucket('gpdb-4.3.10.0-concourse', exists_in_s3 = True)
    aws = self.MockAWS(bucket)
    release_with_bad_aws = release.Release('4.3.10.0', '123abc', aws=aws)

    release_with_bad_aws.create_release_bucket()
    assert_that(bucket.was_created, equal_to(False))

  def test_set_bucket_policy(self):
    bucket = self.MockBucket('gpdb-4.3.10.0-concourse', exists_in_s3 = True)
    aws = self.MockAWS(bucket)
    release_with_aws = release.Release('4.3.10.0', '123abc', aws=aws)

    release_with_aws.set_bucket_policy()
    policy = json.loads(bucket.bucket_policy.policy_json)
    expected_policy = self.aws_policy('arn:aws:s3:::gpdb-4.3.10.0-concourse/*', 'arn:aws:iam::118837423556:root')
    assert_that(policy, equal_to(expected_policy))

  def aws_policy(self, resource, principal):
    return {
      u'Version': u'2008-10-17',
      u'Statement': [{
        u'Action': [u's3:GetObject', u's3:GetObjectVersion'],
        u'Resource': resource,
        u'Effect': u'Allow',
        u'Principal': {u'AWS': principal}
      }]}

  def test_set_bucket_versioning(self):
    bucket = self.MockBucket('gpdb-4.3.10.0-concourse', exists_in_s3 = True)
    aws = self.MockAWS(bucket)
    release_with_aws = release.Release('4.3.10.0', '123abc', aws=aws)

    release_with_aws.set_bucket_versioning()
    assert_that(bucket.bucket_versioning.status, equal_to('Enabled'))

class Spy(object):
  def __init__(self, returns=None):
    self.calls = 0
    self.returns = returns
  def __call__(self, *args, **kwargs):
    self.last_args = args
    self.last_kwargs = kwargs
    self.calls += 1
    return self.returns


class MockPrinter(object):
  def print_msg(self, msg):
    pass


class CheckEnvironmentsTest(unittest.TestCase):
  class MockEnvironment(object):
    def __init__(self):
      self.check_dependencies = Spy(returns=True)
      self.check_git_can_pull = Spy(returns=True)
      self.check_git_status = Spy(returns=True)
      self.check_git_head_is_latest = Spy(returns=True)
      self.check_has_file = Spy(returns=True)

  def setUp(self):
    self.gpdb_environment = self.MockEnvironment()
    self.secrets_environment = self.MockEnvironment()

  def test_checks_both_git_repositories(self):
    ret = release.check_environments(self.gpdb_environment, self.secrets_environment, printer=MockPrinter())
    assert_that(ret)

    assert_that(self.gpdb_environment.check_dependencies.calls, greater_than(0))
    assert_that(self.gpdb_environment.check_git_can_pull.calls, greater_than(0))
    assert_that(self.gpdb_environment.check_git_status.calls, greater_than(0))
    assert_that(self.secrets_environment.check_git_can_pull.calls, greater_than(0))
    assert_that(self.secrets_environment.check_git_status.calls, greater_than(0))
    assert_that(self.secrets_environment.check_git_head_is_latest.calls, greater_than(0))
    assert_that(self.secrets_environment.check_has_file.calls, equal_to(1))
    assert_that(self.secrets_environment.check_has_file.last_args[0], equal_to('gpdb-4.3_STABLE-ci-secrets.yml'))

  def test_one_fails_but_still_runs_all(self):
    for i, failing_method in enumerate((
        self.gpdb_environment.check_dependencies,
        self.gpdb_environment.check_git_status,
        self.secrets_environment.check_git_status)):
      try:
        failing_method.returns = False

        ret = release.check_environments(self.gpdb_environment, self.secrets_environment, printer=MockPrinter())
        assert_that(ret, equal_to(False))

        assert_that(self.gpdb_environment.check_dependencies.calls, equal_to(i+1))
        assert_that(self.gpdb_environment.check_git_status.calls, equal_to(i+1))
        assert_that(self.secrets_environment.check_git_status.calls, equal_to(i+1))
      finally:
        failing_method.returns = True

  def test_fails_from_multiple_failures(self):
    self.gpdb_environment.check_dependencies.returns = False
    self.secrets_environment.check_git_status.returns = False

    ret = release.check_environments(self.gpdb_environment, self.secrets_environment, printer=MockPrinter())
    assert_that(ret, equal_to(False))

  def test_checks_for_template_secrets_file(self):
    ret = release.check_environments(self.gpdb_environment, self.secrets_environment, printer=MockPrinter())
    assert_that(ret, equal_to(True))
    assert_that(self.secrets_environment.check_has_file.calls, equal_to(1))
    assert_that(self.secrets_environment.check_has_file.last_args[0], equal_to('gpdb-4.3_STABLE-ci-secrets.yml'))

  def test_checks_for_template_secrets_file_missing(self):
    self.secrets_environment.check_has_file.returns = False
    ret = release.check_environments(self.gpdb_environment, self.secrets_environment, printer=MockPrinter())
    assert_that(ret, equal_to(False))
    assert_that(self.secrets_environment.check_has_file.calls, equal_to(1))
    assert_that(self.secrets_environment.check_has_file.last_args[0], equal_to('gpdb-4.3_STABLE-ci-secrets.yml'))


if __name__ == '__main__':
    unittest.main()
