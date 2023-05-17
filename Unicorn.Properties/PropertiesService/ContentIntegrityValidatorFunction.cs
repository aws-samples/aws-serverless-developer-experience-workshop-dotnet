// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json;
using System.Text.Json.Nodes;
using Amazon.Lambda.Core;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using AWS.Lambda.Powertools.Logging;
using AWS.Lambda.Powertools.Metrics;
using AWS.Lambda.Powertools.Tracing;

// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Unicorn.Properties.PropertiesService;

/// <summary>
/// Represents the AWS Lambda function that checks the integrity of the property details
/// </summary>
public class ContentIntegrityValidatorFunction
{
    /// <summary>
    /// Default constructor. Initialises global variables for function.
    /// </summary>
    /// <exception cref="Exception">Init exception</exception>
    public ContentIntegrityValidatorFunction()
    {
        // Instrument all AWS SDK calls
        AWSSDKHandler.RegisterXRayForAllServices();
    }


    /// <summary>
    /// Event handler for ContractStatusChangedEvent
    /// </summary>
    /// <param name="input">The input payload</param>
    /// <param name="context">Lambda Context runtime methods and attributes</param>
    [Logging(LogEvent = true)]
    [Metrics(CaptureColdStart = true)]
    [Tracing(CaptureMode = TracingCaptureMode.ResponseAndError)]
    public object FunctionHandler(object input, ILambdaContext context)
    {
        var status = "PASS";
        var document = JsonSerializer.SerializeToDocument(input);
        
        foreach (var imageModerationElement in document.RootElement.GetProperty("ImageModerations").EnumerateArray())
        {
            if (imageModerationElement.GetProperty("ModerationLabels").GetArrayLength() > 0)
            {
                status = "FAIL";
                break;
            }
        }

        var sentiment = document.RootElement.GetProperty("ContentSentiment").GetProperty("Sentiment").GetString();
        if (!string.Equals(sentiment, "POSITIVE", StringComparison.CurrentCultureIgnoreCase))
        {
            status = "FAIL";
        }
        
        var jsonObject = JsonObject.Create(document.RootElement);
        jsonObject.Add("ValidationResult", status);  //TODO: review this implementation
        return jsonObject;
    }
}