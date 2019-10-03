import setuptools


setuptools.setup(
    name='schema-registry-tests',
    version='0.0.1',
    author="Confluent, Inc.",
    author_email="connect-team@confluent.io",
    description='Schema registry docker image tests',
    url="https://github.com/confluentinc/schema-registry-images",
    dependency_links=open("requirements.txt").read().split("\n"),
    packages=['test'],
    include_package_data=True,
    python_requires='>=2.7',
    setup_requires=['setuptools-git'],
)
