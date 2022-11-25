// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;

namespace Unicorn.Contracts.ContractService;

/// <summary>
/// The exception that is thrown when no Contract can be found.
/// </summary>
[Serializable]
public class ContractNotFoundException : Exception
{
    public ContractNotFoundException(string message) : base(message)
    {
    }

    public ContractNotFoundException(string message, Exception innerException) : base(message, innerException)
    {
    }
}