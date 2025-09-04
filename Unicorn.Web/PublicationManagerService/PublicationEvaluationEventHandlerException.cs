// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

namespace Unicorn.Web.PublicationManagerService;

/// <summary>
/// Represents the exception that is thrown when a Publication Approved event handler cannot process the event.
/// </summary>
[Serializable]
public class PublicationEvaluationEventHandlerException : Exception
{
    public PublicationEvaluationEventHandlerException(string message) : base(message)
    {
    }

    public PublicationEvaluationEventHandlerException(string message, Exception innerException) : base(message,
        innerException)
    {
    }
}