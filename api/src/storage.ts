import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { BlobServiceClient } from '@azure/storage-blob';

export interface ImageStorage {
  put(id: string, bytes: Buffer, contentType: string): Promise<void>;
  get(id: string): Promise<Buffer | null>;
  delete(id: string): Promise<void>;
}

const required = (name: string): string => {
  const value = process.env[name];
  if (!value) throw new Error(`Storage-Konfiguration unvollständig: ${name} fehlt.`);
  return value;
};

class LocalStorage implements ImageStorage {
  constructor(private readonly directory: string) {}
  private path(id: string): string { return join(this.directory, id); }
  async put(id: string, bytes: Buffer): Promise<void> {
    await mkdir(this.directory, { recursive: true });
    await writeFile(this.path(id), bytes, { mode: 0o600 });
  }
  async get(id: string): Promise<Buffer | null> {
    try { return await readFile(this.path(id)); }
    catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null; throw error; }
  }
  async delete(id: string): Promise<void> { await rm(this.path(id), { force: true }); }
}

class S3Storage implements ImageStorage {
  private readonly client: S3Client;
  private readonly bucket: string;
  constructor() {
    const endpoint = required('S3_ENDPOINT');
    this.bucket = required('S3_BUCKET');
    this.client = new S3Client({
      endpoint,
      region: process.env.S3_REGION || 'eu-central-1',
      forcePathStyle: process.env.S3_FORCE_PATH_STYLE !== 'false',
      credentials: { accessKeyId: required('S3_ACCESS_KEY_ID'), secretAccessKey: required('S3_SECRET_ACCESS_KEY') },
    });
  }
  async put(id: string, bytes: Buffer, contentType: string): Promise<void> {
    await this.client.send(new PutObjectCommand({ Bucket: this.bucket, Key: id, Body: bytes, ContentType: contentType }));
  }
  async get(id: string): Promise<Buffer | null> {
    try {
      const result = await this.client.send(new GetObjectCommand({ Bucket: this.bucket, Key: id }));
      return result.Body ? Buffer.from(await result.Body.transformToByteArray()) : null;
    } catch (error) { if ((error as { name?: string }).name === 'NoSuchKey' || (error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode === 404) return null; throw error; }
  }
  async delete(id: string): Promise<void> { await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: id })); }
}

class AzureBlobStorage implements ImageStorage {
  private readonly container;
  constructor() {
    this.container = BlobServiceClient.fromConnectionString(required('AZURE_STORAGE_CONNECTION_STRING'))
      .getContainerClient(process.env.AZURE_STORAGE_CONTAINER || 'chicken-images');
  }
  async put(id: string, bytes: Buffer, contentType: string): Promise<void> {
    await this.container.createIfNotExists();
    await this.container.getBlockBlobClient(id).uploadData(bytes, { blobHTTPHeaders: { blobContentType: contentType } });
  }
  async get(id: string): Promise<Buffer | null> {
    try { return await this.container.getBlockBlobClient(id).downloadToBuffer(); }
    catch (error) { if ((error as { statusCode?: number }).statusCode === 404) return null; throw error; }
  }
  async delete(id: string): Promise<void> { await this.container.getBlockBlobClient(id).deleteIfExists(); }
}

export function createStorage(): ImageStorage {
  switch (process.env.STORAGE_DRIVER || 'local') {
    case 'local': return new LocalStorage(process.env.LOCAL_STORAGE_PATH || '/data/images');
    case 's3': return new S3Storage();
    case 'azure-blob': return new AzureBlobStorage();
    default: throw new Error('STORAGE_DRIVER muss local, s3 oder azure-blob sein.');
  }
}
