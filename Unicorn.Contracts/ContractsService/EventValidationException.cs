// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;

namespace Unicorn.Contracts.ContractService;

/// <summary>
/// The exception that is thrown when an event cannot be validated.
/// </summary>
[Serializable]
public class EventValidationException : Exception
{
    public EventValidationException(string message) : base(message)
    {
    }

    public EventValidationException(string message, Exception innerException) : base(message, innerException)
    {
    }
}