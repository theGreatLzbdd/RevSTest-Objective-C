//
//  RSListener.m
//  RevS
//
//  Created by Zebang Liu on 13-8-1.
//  Copyright (c) 2013年 Zebang Liu. All rights reserved.
//  Contact: the.great.lzbdd@gmail.com
/*
 This file is part of RevS.
 
 RevS is free software: you can redistribute it and/or modify
 it under the terms of the GNU Lesser General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 RevS is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU Lesser General Public License for more details.
 
 You should have received a copy of the GNU Lesser General Public License
 along with RevS.  If not, see <http://www.gnu.org/licenses/>.
 */


#import "RevS.h"

@interface RSListener () <RSMessengerDelegate>

@end

@implementation RSListener

@synthesize delegates;

+ (RSListener *)sharedListener
{
    static RSListener *listener;
    if (!listener) {
        listener = [[RSListener alloc]init];
        listener.delegates = [NSMutableArray array];
    }
    return listener;
}

+ (void)addDelegate:(id <RSListenerDelegate>)delegate
{
    if (![[RSListener sharedListener].delegates containsObject:delegate]) {
        [[RSListener sharedListener].delegates addObject:delegate];
    }
}

#pragma mark - RSMessageDelegate

- (void)messenger:(RSMessenger *)messenger didRecieveMessageWithIdentifier:(NSString *)identifier arguments:(NSArray *)arguments tag:(NSInteger)tag
{
    NSString *messageType = identifier;
    NSArray *messageArguments = arguments;
    if ([messageType isEqualToString:@"S"]) {
        //Someone requested a search
        NSString *requesterPublicIP = [messageArguments objectAtIndex:0];
        NSString *requesterPrivateIP = [messageArguments objectAtIndex:1];
        NSString *senderPublicIP = [messageArguments objectAtIndex:2];
        NSString *senderPrivateIP = [messageArguments objectAtIndex:3];
        NSString *fileName = [messageArguments objectAtIndex:4];
        NSUInteger ttl = [[messageArguments objectAtIndex:5] integerValue];
        ttl -= 1;
        if (ttl > 0) {
            if ([[RSUtilities listOfFilenames]containsObject:fileName]) {
                //Ooh,you have the file!First,send a message to the sender to increase the probability index on this path
                NSString *incIndexMessageString = [RSMessenger messageWithIdentifier:@"INC" arguments:@[[NSString stringWithFormat:@"%ld",(unsigned long)INDEX_INC],[RSUtilities publicIpAddress],[RSUtilities privateIPAddress],fileName]];
                RSMessenger *incIndexMessage = [RSMessenger messengerWithPort:DOWNLOAD_PORT];
                [incIndexMessage addDelegate:self];
                [incIndexMessage sendUdpMessage:incIndexMessageString toHostWithPublicAddress:senderPublicIP privateAddress:senderPrivateIP tag:0];
                
                //Next,tell the requester that you have the file
                NSString *string = [RSMessenger messageWithIdentifier:@"HASFILE" arguments:@[fileName,[RSUtilities publicIpAddress],[RSUtilities privateIPAddress]]];
                RSMessenger *message = [RSMessenger messengerWithPort:DOWNLOAD_PORT];
                [message addDelegate:self];
                [message sendUdpMessage:string toHostWithPublicAddress:requesterPublicIP privateAddress:requesterPrivateIP tag:0];
            }
            else {
                //You don't have the file,so send a message to one of the neighbors
                [[NSUserDefaults standardUserDefaults]setObject:[NSString stringWithFormat:@"%@,%@",senderPublicIP,senderPrivateIP] forKey:[NSString stringWithFormat:@"%@:sender",[RSUtilities hashFromString:fileName]]];
                NSArray *contactList = [RSUtilities contactListWithKValue:K_NEIGHBOR];
                for (NSString *string in contactList) {
                    NSString *publicIP = [[string componentsSeparatedByString:@","] objectAtIndex:0];
                    NSString *privateIP = [[string componentsSeparatedByString:@","] objectAtIndex:1];
                    if (![requesterPublicIP isEqualToString:publicIP]) {
                        NSString *messageString = [RSMessenger messageWithIdentifier:@"S" arguments:@[requesterPublicIP,requesterPrivateIP,[RSUtilities publicIpAddress],[RSUtilities privateIPAddress],fileName,[NSString stringWithFormat:@"%ld",(unsigned long)ttl]]];
                        RSMessenger *message = [RSMessenger messengerWithPort:DOWNLOAD_PORT];
                        [message addDelegate:self];
                        [message sendUdpMessage:messageString toHostWithPublicAddress:publicIP privateAddress:privateIP tag:0];
                    }
                }
            }
        }
    }
    else if ([messageType isEqualToString:@"INC"]) {
        NSUInteger inc = [[messageArguments objectAtIndex:0] integerValue];
        NSString *senderPublicIP = [messageArguments objectAtIndex:1];
        NSString *senderPrivateIP = [messageArguments objectAtIndex:2];
        NSString *fileName = [messageArguments objectAtIndex:3];
        
        //Change probability index
        NSString *dataString = [NSData decryptData:[NSData dataWithContentsOfFile:PROB_INDEX_PATH] withKey:FILE_CODE];
        NSMutableArray *dataArray = [NSMutableArray arrayWithArray:[dataString componentsSeparatedByString:@"/"]];
        
        NSMutableArray *probIndexList = [NSMutableArray array];
        NSMutableArray *probIndexContactList = [NSMutableArray array];
        for (NSString *string in dataArray) {
            NSArray *array = [string componentsSeparatedByString:@":"];
            NSString *ipAddress = [array objectAtIndex:0];
            NSNumber *probIndex = [NSNumber numberWithInteger:[[array lastObject]integerValue]];
            [probIndexContactList addObject:ipAddress];
            [probIndexList addObject:probIndex];
        }
        NSUInteger senderProbIndex = [[probIndexList objectAtIndex:[probIndexContactList indexOfObject:[NSString stringWithFormat:@"%@,%@",senderPublicIP,senderPrivateIP]]] integerValue];
        senderProbIndex += inc;
        [dataArray replaceObjectAtIndex:[probIndexContactList indexOfObject:[NSString stringWithFormat:@"%@,%@",senderPublicIP,senderPrivateIP]] withObject:[NSString stringWithFormat:@"%@:%ld",[NSString stringWithFormat:@"%@,%@",senderPublicIP,senderPrivateIP],(unsigned long)senderProbIndex]];
        NSString *newProbIndexString = [dataArray componentsJoinedByString:@"/"];
        [[NSData encryptString:newProbIndexString withKey:FILE_CODE]writeToFile:PROB_INDEX_PATH atomically:YES];
        
        //Pass on the message
        NSString *senderKey = [NSString stringWithFormat:@"%@:sender",[RSUtilities hashFromString:fileName]];
        NSString *string = [[NSUserDefaults standardUserDefaults]objectForKey:senderKey];
        [[NSUserDefaults standardUserDefaults]removeObjectForKey:senderKey];
        if (string) {
            NSString *publicIP = [[string componentsSeparatedByString:@","] objectAtIndex:0];
            NSString *privateIP = [[string componentsSeparatedByString:@","] objectAtIndex:1];
            NSString *incIndexMessageString = [RSMessenger messageWithIdentifier:@"INC" arguments:@[[NSString stringWithFormat:@"%ld",(unsigned long)INDEX_INC],[RSUtilities publicIpAddress],[RSUtilities privateIPAddress],fileName]];
            RSMessenger *incIndexMessage = [RSMessenger messengerWithPort:DOWNLOAD_PORT];
            [incIndexMessage addDelegate:self];
            [incIndexMessage sendUdpMessage:incIndexMessageString toHostWithPublicAddress:publicIP privateAddress:privateIP tag:0];
        }
    }
    else if ([messageType isEqualToString:@"JOIN"]) {
        NSString *deviceHash = [messageArguments objectAtIndex:0];
        NSString *publicIP = [messageArguments objectAtIndex:1];
        NSString *privateIP = [messageArguments objectAtIndex:2];
        NSString *dataString = [NSData decryptData:[NSData dataWithContentsOfFile:IP_LIST_PATH] withKey:FILE_CODE];
        NSMutableArray *dataArray = [NSMutableArray arrayWithArray:[dataString componentsSeparatedByString:@";"]];
        for (NSString *string in dataArray) {
            NSArray *array = [string componentsSeparatedByString:@"|"];
            NSString *hash = [array objectAtIndex:0];
            NSString *neighborPublicAddress = [[[array objectAtIndex:1]componentsSeparatedByString:@","] objectAtIndex:0];
            NSString *neighborPrivateAddress = [[[array objectAtIndex:1]componentsSeparatedByString:@","] objectAtIndex:1];
            if ([deviceHash isEqualToString:hash]) {
                NSString *newDataString = [NSString stringWithFormat:@"%@|%@,%@|1",hash,publicIP,privateIP];
                [dataArray replaceObjectAtIndex:[dataArray indexOfObject:string] withObject:newDataString];
            }
        }
        NSString *ipListString = [dataArray componentsJoinedByString:@";"];
        [[NSData encryptString:ipListString withKey:FILE_CODE]writeToFile:IP_LIST_PATH atomically:YES];
    }
    else if ([messageType isEqualToString:@"QUIT"]) {
        NSString *deviceHash = [messageArguments objectAtIndex:0];
        NSString *publicIP = [messageArguments objectAtIndex:1];
        NSString *privateIP = [messageArguments objectAtIndex:2];
        NSString *dataString = [NSData decryptData:[NSData dataWithContentsOfFile:IP_LIST_PATH] withKey:FILE_CODE];
        NSMutableArray *dataArray = [NSMutableArray arrayWithArray:[dataString componentsSeparatedByString:@";"]];
        for (NSString *string in dataArray) {
            NSArray *array = [string componentsSeparatedByString:@"|"];
            NSString *hash = [array objectAtIndex:0];
            NSString *neighborPublicAddress = [[[array objectAtIndex:1]componentsSeparatedByString:@","] objectAtIndex:0];
            NSString *neighborPrivateAddress = [[[array objectAtIndex:1]componentsSeparatedByString:@","] objectAtIndex:1];
            if ([deviceHash isEqualToString:hash]) {
                NSString *newDataString = [NSString stringWithFormat:@"%@|%@,%@|0",hash,publicIP,privateIP];
                [dataArray replaceObjectAtIndex:[dataArray indexOfObject:string] withObject:newDataString];
            }
        }
        NSString *ipListString = [dataArray componentsJoinedByString:@";"];
        [[NSData encryptString:ipListString withKey:FILE_CODE]writeToFile:IP_LIST_PATH atomically:YES];
    }
    else if ([messageType isEqualToString:@"HASFILE"])
    {
        NSString *fileName = [messageArguments objectAtIndex:0];
        if (![[NSUserDefaults standardUserDefaults]boolForKey:[NSString stringWithFormat:@"%@:gotAHit",fileName]]) {
            NSString *fileOwnerPublicIP = [messageArguments objectAtIndex:1];
            NSString *fileOwnerPrivateIP = [messageArguments objectAtIndex:2];
            [[NSUserDefaults standardUserDefaults]setBool:YES forKey:[NSString stringWithFormat:@"%@:gotAHit",fileName]];
            RSMessenger *message = [RSMessenger messengerWithPort:DOWNLOAD_PORT];
            [message addDelegate:self];
            [message sendUdpMessage:[RSMessenger messageWithIdentifier:@"DFILE" arguments:@[fileName,[RSUtilities publicIpAddress],[RSUtilities privateIPAddress]]] toHostWithPublicAddress:fileOwnerPublicIP privateAddress:fileOwnerPrivateIP tag:0];
        }
    }
    else if ([messageType isEqualToString:@"DFILE"])
    {
        NSString *fileName = [messageArguments objectAtIndex:0];
        NSString *requesterPublicIP = [messageArguments objectAtIndex:1];
        NSString *requesterPrivateIP = [messageArguments objectAtIndex:2];
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithFormat:@"%@%@",STORED_DATA_DIRECTORY,fileName]];
        NSString *dataString = [NSData decryptData:data withKey:FILE_CODE];//[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *string = [RSMessenger messageWithIdentifier:@"FILE" arguments:@[fileName,dataString]];
        RSMessenger *message = [RSMessenger messengerWithPort:DOWNLOAD_PORT];
        [message addDelegate:self];
        [message sendUdpMessage:string toHostWithPublicAddress:requesterPublicIP privateAddress:requesterPrivateIP tag:0];
    }
    else if ([messageType isEqualToString:@"FILE"]) {
        NSString *fileName = [messageArguments objectAtIndex:0];
        NSString *dataString = [messageArguments objectAtIndex:1];
        NSData *data = [NSData encryptString:dataString withKey:FILE_CODE];
        [data writeToFile:[NSString stringWithFormat:@"%@%@",STORED_DATA_DIRECTORY,fileName] atomically:YES];
        for (id delegate in delegates) {
            if ([delegate respondsToSelector:@selector(didSaveFile:)]) {
                [delegate didSaveFile:fileName];
            }
        }
    }
    else if ([messageType isEqualToString:@"UFILE"])
    {
        NSString *fileName = [messageArguments objectAtIndex:0];
        NSString *fileOwnerPublicIP = [messageArguments objectAtIndex:1];
        NSString *fileOwnerPrivateIP = [messageArguments objectAtIndex:2];
        NSUInteger timeToLive = [[messageArguments objectAtIndex:3] integerValue];
        RSMessenger *message = [RSMessenger messengerWithPort:UPLOAD_PORT];
        [message addDelegate:self];
        [message sendUdpMessage:[RSMessenger messageWithIdentifier:@"ASKFILE" arguments:@[fileName,[RSUtilities publicIpAddress],[RSUtilities privateIPAddress],[NSString stringWithFormat:@"%ld",(unsigned long)timeToLive]]] toHostWithPublicAddress:fileOwnerPublicIP privateAddress:fileOwnerPrivateIP tag:0];
    }
    else if ([messageType isEqualToString:@"ASKFILE"])
    {
        NSString *fileName = [messageArguments objectAtIndex:0];
        NSString *requesterPublicIP = [messageArguments objectAtIndex:1];
        NSString *requesterPrivateIP = [messageArguments objectAtIndex:2];
        NSUInteger timeToLive = [[messageArguments objectAtIndex:3] integerValue];
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithFormat:@"%@%@",STORED_DATA_DIRECTORY,fileName]];
        NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *string = [RSMessenger messageWithIdentifier:@"SENDFILE" arguments:@[fileName,dataString,[NSString stringWithFormat:@"%ld",(unsigned long)timeToLive],requesterPublicIP,requesterPrivateIP]];
        RSMessenger *message = [RSMessenger messengerWithPort:DOWNLOAD_PORT];
        [message addDelegate:self];
        [message sendUdpMessage:string toHostWithPublicAddress:requesterPublicIP privateAddress:requesterPrivateIP tag:0];
        for (id delegate in delegates) {
            if ([delegate respondsToSelector:@selector(didUploadFile:)]) {
                [delegate didUploadFile:fileName];
            }
        }
    }
    else if ([messageType isEqualToString:@"SENDFILE"]) {
        NSString *fileName = [messageArguments objectAtIndex:0];
        NSString *dataString = [messageArguments objectAtIndex:1];
        NSUInteger timeToLive = [[messageArguments objectAtIndex:2] integerValue];
        NSString *uploaderPublicIP = [messageArguments objectAtIndex:3];
        NSString *uploaderPrivateIP = [messageArguments objectAtIndex:4];
        timeToLive -= 1;
        NSData *data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
        NSString *string = [RSMessenger messageWithIdentifier:@"UFILE" arguments:@[fileName,[RSUtilities publicIpAddress],[RSUtilities privateIPAddress],[NSString stringWithFormat:@"%ld",(unsigned long)timeToLive]]];
        //Prevent error
        if ([RSUtilities freeDiskspace] < data.length) {
            string = [RSMessenger messageWithIdentifier:@"UFILE" arguments:@[fileName,uploaderPublicIP,uploaderPrivateIP,[NSString stringWithFormat:@"%ld",timeToLive + 1]]];
        }
        else
        {
            [data writeToFile:[NSString stringWithFormat:@"%@%@",STORED_DATA_DIRECTORY,fileName] atomically:YES];
        }
        if (timeToLive > 0) {
            NSArray *contactList = [RSUtilities contactListWithKValue:K_NEIGHBOR];
            for (NSUInteger i = 0; i < K_UPLOAD; i++) {
                if (i < contactList.count && ![[contactList objectAtIndex:i] isEqualToString:[NSString stringWithFormat:@"%@,%@",uploaderPublicIP,uploaderPrivateIP]]) {
                    NSString *contactPublicIP = [[[contactList objectAtIndex:i] componentsSeparatedByString:@","] objectAtIndex:0];
                    NSString *contactPrivateIP = [[[contactList objectAtIndex:i] componentsSeparatedByString:@","] objectAtIndex:1];
                    RSMessenger *message = [RSMessenger messengerWithPort:UPLOAD_PORT];
                    [message addDelegate:[RSListener sharedListener]];
                    [message sendUdpMessage:string toHostWithPublicAddress:contactPublicIP privateAddress:contactPrivateIP tag:0];
                }
            }
        }
                
        for (id delegate in delegates) {
            if ([delegate respondsToSelector:@selector(didSaveFile:)]) {
                [delegate didSaveFile:fileName];
            }
        }
    }
}

@end