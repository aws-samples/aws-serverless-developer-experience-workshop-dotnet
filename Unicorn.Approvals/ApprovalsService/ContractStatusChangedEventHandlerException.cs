// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

namespace Unicorn.Approvals.ApprovalsService;
/// <summary>
/// Represents the exception that is thrown when a Contract Status Changed event handler cannot process the event.
/// </summary>
[Serializable]
public class ContractStatusChangedEventHandlerException : Exception
{
    public ContractStatusChangedEventHandlerException(string message) : base(message)
    {
    }

    public ContractStatusChangedEventHandlerException(string message, Exception innerException) : base(message,
        innerException)
    {
    }
}