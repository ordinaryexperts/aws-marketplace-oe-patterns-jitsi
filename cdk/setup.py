import setuptools

CDK_VERSION="2.225.0"
OE_PATTERNS_CDK_COMMON_VERSION="4.5.0"

setuptools.setup(
    name="jitsi",
    package_dir={"": "jitsi"},
    packages=setuptools.find_packages(where="jitsi"),
    install_requires=[
        f"aws-cdk-lib=={CDK_VERSION}",
        f"constructs>=10.0.0,<11.0.0",
        f"oe-patterns-cdk-common@git+https://github.com/ordinaryexperts/aws-marketplace-oe-patterns-cdk-common@{OE_PATTERNS_CDK_COMMON_VERSION}"
    ],
)
