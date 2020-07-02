import setuptools


with open("README.md") as fp:
    long_description = fp.read()


CDK_VERSION="1.49.0"

setuptools.setup(
    name="jisti",
    version="0.0.1",

    description="An empty CDK Python app",
    long_description=long_description,
    long_description_content_type="text/markdown",

    author="author",

    package_dir={"": "jitsi"},
    packages=setuptools.find_packages(where="jitsi"),

    install_requires=[
        f"aws-cdk.aws-autoscaling=={CDK_VERSION}",
        f"aws-cdk.aws-cloudwatch=={CDK_VERSION}",
        f"aws-cdk.aws-ec2=={CDK_VERSION}",
        f"aws-cdk.aws-iam=={CDK_VERSION}",
        f"aws-cdk.aws-sns=={CDK_VERSION}",
        f"aws-cdk.core=={CDK_VERSION}"
    ],

    python_requires=">=3.6",

    classifiers=[
        "Development Status :: 4 - Beta",

        "Intended Audience :: Developers",

        "License :: OSI Approved :: Apache Software License",

        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.6",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",

        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",

        "Typing :: Typed",
    ],
)
