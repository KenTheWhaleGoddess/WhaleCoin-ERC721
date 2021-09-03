import os
from PIL import Image
import logging
import json
import boto3
import requests
from botocore.exceptions import ClientError
from io import StringIO
import urllib.request

def resize_pixelate(filename, x, pixel_size):
    extension = filename.split(".")[-1]
    image = Image.open(filename)
    #inputs are desired size of output image
    image = image.resize((400,300))
    image = image.resize(
        (image.size[0] // pixel_size, image.size[1] // pixel_size),
        Image.NEAREST
    )
    image = image.resize(
        (image.size[0] * pixel_size, image.size[1] * pixel_size),
        Image.NEAREST
    )
    imgSrc = f"img/whale{x}.{extension}"
    # set your desired file_name here,  will be saved with same extension/format of raw image
    image.save(imgSrc)
    return imgSrc

def upload_file(file_name, bucket, object_name=None):
    """Upload a file to an S3 bucket

    :param file_name: File to upload
    :param bucket: Bucket to upload to
    :param object_name: S3 object name. If not specified then file_name is used
    :return: True if file was uploaded, else False
    """

    # If S3 object_name was not specified, use file_name
    if object_name is None:
        object_name = os.path.basename(file_name)

    # Upload the file
    s3_client = boto3.client('s3')
    try:
        s3_client.upload_file(file_name, bucket, object_name)
        return True
    except ClientError as e:
        logging.error(e)
        return False

def generateMetadata(filename, x):
    extension = filename.split(".")[-1]
    return {
        "name": f"WhaleCoin #{x}",
        "description": "A one of a kind WhaleCoin programmatically generated"
            + " by WhaleGoddess.",
        "image": f"https://whalecoin-img.s3.us-west-1.amazonaws.com/whale{x}.{extension}",
        "attributes": {
            "luck": 1
        }
    }

def saveMetadata(md, x):
    # Serializing json 
    json_object = json.dumps(md)
  
    # Writing to sample.json
    with open(f"md/{x}", "w") as outfile:
        outfile.write(json_object)
    return True

def findTenWhalesOnGoogle(n):
    count = 0
    googleSearchApiAccessKey = 'Get your own access key : https://developers.google.com/custom-search/v1/overview'
    images = []
    apiCall = 'https://customsearch.googleapis.com/customsearch/v1?c2coff=1&cx=2fcd0024cf7d6bee6&q=whale&excludeTerms=nft&fileType=png&filter=1&imgColorType=imgColorTypeUndefined&imgDominantColor=imgDominantColorUndefined&imgSize=imgSizeUndefined&imgType=animated&searchType=image&key=' + googleSearchApiAccessKey
    page = requests.get(apiCall).json()
    items = page['items']
    for value in items:
        images.append(value['link'])
        count += 1
        
    return images


x = 0
imgBucket = 'whalecoin-img'
mdBucket = 'whalecoin-md'
try:
    googleSearchResults = findTenWhalesOnGoogle(30)
except:
    print("Couldn't call Google API.")
    raise

for item in googleSearchResults:
    try:
        itemSrc = f"src/{x}.png"
        urllib.request.urlretrieve(item, itemSrc)

        result = resize_pixelate(itemSrc, x, 6) # third arg is size of pixels

        md = generateMetadata(result, x)
        saveMetadata(md, x)
        print(md)
        print("uploading to s3")
        print(upload_file(result, imgBucket))
        print(upload_file(f"md/{x}", mdBucket))
        x += 1
    except:
        print("Bruh moment when saving files.")
        raise

print("I think it worked!")
print("Check: ")
