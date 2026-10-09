# Security Policy

This document outlines supported versions, reporting procedures, and the unique security posture of compiling Mojo code into WebAssembly modules.

## Supported Versions

Use this section to tell people about which versions of your project are
currently being supported with security updates.

| Version | Supported          |
| ------- | ------------------ |
Beta      | ✅

## Reporting a Vulnerability

**Please do not open public GitHub issues, discussions, or pull requests for security vulnerabilities.** Public exposure endangers projects consuming our compiled Wasm modules.

Instead, please submit vulnerabilities through one of the following private methods:
* **Private Vulnerability Reporting:** Use the native GitHub "Report a vulnerability" button under the **Security** tab of this repository.
* **Email:** ravidave550@gmail.com

### What to Include in Your Report
To accelerate remediation, please include:
* A detailed description of the vulnerability (e.g., memory corruption, cross-boundary data leakage).
* The specific version, target Mojo compiler version, and runtime platform (e.g., V8, Wasmer, Wasmtime).
* A minimal, reproducible proof of concept (PoC) script/Mojo snippet.
* The potential impact on host applications embedding the Wasm binary.

## Recommended Execution Policies

If you run our compiled Wasm artifacts in production web environments, we strongly advise enforcing a strict **Content Security Policy (CSP).**
