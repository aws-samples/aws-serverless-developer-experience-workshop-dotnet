// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

namespace Unicorn.Properties.PropertiesService;

/// <summary>
/// Represents the exception that is thrown when a Contract Status cannot be found.
/// </summary>
[Serializable]
public class ContractStatusNotFoundException : Exception
{
    public ContractStatusNotFoundException(string message) : base(message)
    {
    }

    public ContractStatusNotFoundException(string message, Exception innerException) : base(message, innerException)
    {
    }
}